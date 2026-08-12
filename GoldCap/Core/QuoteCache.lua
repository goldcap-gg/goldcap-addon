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

function GC.QuoteCache.Get(cache, itemID, now)
  local quote = cache[itemID]
  if not quote then return nil end
  if now - quote.at > GC.QuoteCache.MAX_AGE_SECONDS then
    cache[itemID] = nil
    return nil
  end
  return quote.unit
end

function GC.QuoteCache.Clear(cache)
  for itemID in pairs(cache) do
    cache[itemID] = nil
  end
end
