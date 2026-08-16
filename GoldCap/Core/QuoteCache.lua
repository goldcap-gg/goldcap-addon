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

-- `maxAge` overrides MAX_AGE_SECONDS for one call. The Sniper's 10s window exists because a
-- purchase is decided against a single price point and a stale one loses gold; a Sell-side quote
-- backs a *listing*, which competes over hours, so the Sell tab passes a wider window rather than
-- making Post unclickable for want of a quote that expired between the query and the click.
function GC.QuoteCache.Fresh(cache, itemID, now, maxAge)
  local quote = validEntry(cache, itemID, now)
  local limit = type(maxAge) == "number" and maxAge > 0 and maxAge or GC.QuoteCache.MAX_AGE_SECONDS
  if not quote or quote.stale == true or quote.fresh == false
      or now - quote.at > limit then return nil end
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
