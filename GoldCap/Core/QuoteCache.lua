local _, GC = ...

GC.QuoteCache = {}

GC.QuoteCache.MAX_AGE_SECONDS = 10

function GC.QuoteCache.Set(cache, itemID, unit, now)
  if type(unit) ~= "number" or unit <= 0 then
    cache[itemID] = nil
    return
  end
  cache[itemID] = { unit = unit, at = now }
end

function GC.QuoteCache.Latest(cache, itemID)
  return cache[itemID]
end

function GC.QuoteCache.Fresh(cache, itemID, now)
  local quote = GC.QuoteCache.Latest(cache, itemID)
  if not quote or now - quote.at > GC.QuoteCache.MAX_AGE_SECONDS then return nil end
  return quote
end

function GC.QuoteCache.Age(cache, itemID, now)
  local quote = GC.QuoteCache.Latest(cache, itemID)
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
