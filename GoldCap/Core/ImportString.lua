local _, GC = ...

GC.ImportString = { MAX_LEN = 60000 }

-- The one list of regions this addon understands, shared with Core/Data.lua's region
-- detection. Mirrors regionSchema in packages/schema (us/eu/kr/tw): the server has
-- emitted kr and tw import strings ever since those regions started ingesting, and
-- the companion app has known them for as long -- this list refusing them was the
-- only reason those two regions never worked.
GC.ImportString.REGIONS = { us = true, eu = true, kr = true, tw = true }

function GC.ImportString.Parse(str)
  if type(str) ~= "string" then return nil, "empty" end
  if #str > GC.ImportString.MAX_LEN then return nil, "too_long" end
  str = str:gsub("%s+", "")
  if #str == 0 then return nil, "empty" end
  -- Browsers copying a text/plain response often prepend an invisible byte
  -- (UTF-8 BOM, zero-width space) that gsub("%s+") does not strip; drop any
  -- leading junk before the GCS1 marker so a clean paste isn't rejected.
  str = str:match("GCS1;.*") or str

  local region, realm, ts, rest =
    str:match("^GCS1;(%l%l);([%l%d%-]+);(%d+);(.+)$")
  if not region then return nil, "bad_header" end
  -- Distinct from bad_header on purpose: "the string is shaped right but names a region
  -- this build does not know" is the one failure a player can act on (update the addon),
  -- and Core/Data.lua's companion path says exactly that.
  if not GC.ImportString.REGIONS[region] then return nil, "bad_region" end

  local result = {
    region = region, realm = realm, ts = tonumber(ts),
    items = {}, verification = {}, watchlist = {}, namesWanted = {},
  }
  local count = 0

  for section in rest:gmatch("[^;]+") do
    local kind, body = section:match("^(%u):(.+)$")
    if kind == "I" then
      -- 4th field (trend) is a signed 24h market-value momentum percent; it
      -- only ever rides alongside a sold figure (see itemToken's comment in
      -- packages/tsm), so a bare "id=mv" or "id=mv=sold" token still parses
      -- identically to before this field existed.
      for id, mv, sold, trend in body:gmatch("(%d+)=(%d+)=?([%d%.]*)=?(%-?%d*)") do
        local entry = { m = tonumber(mv) }
        if sold ~= "" then entry.s = tonumber(sold) end
        if trend ~= "" then entry.t = tonumber(trend) end
        result.items[tonumber(id)] = entry
        count = count + 1
      end
    elseif kind == "V" then
      -- Verification tokens are deliberately independent from I tokens. A malformed safety
      -- record must not hide its matching market value: it simply leaves that item unverified.
      for token in body:gmatch("[^,]+") do
        local id, sourceAt, stressUnit, sellThroughBps, liquidityConfidence, currentQty,
            listings, observations, madBps, flags = token:match(
              "^(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)$")
        if id then
          result.verification[tonumber(id)] = {
            sourceAt = tonumber(sourceAt),
            stressUnit = tonumber(stressUnit),
            sellThroughBps = tonumber(sellThroughBps),
            liquidityConfidence = tonumber(liquidityConfidence),
            currentQty = tonumber(currentQty),
            listings = tonumber(listings),
            observations = tonumber(observations),
            madBps = tonumber(madBps),
            flags = tonumber(flags),
          }
        end
      end
    elseif kind == "W" then
      for id in body:gmatch("%d+") do
        result.watchlist[#result.watchlist + 1] = tonumber(id)
      end
    elseif kind == "N" then
      -- Item ids the site has no name for (Blizzard's API 404s them). Core/ItemNames.lua
      -- resolves them from the client and the Companion reports the names back.
      for id in body:gmatch("%d+") do
        result.namesWanted[#result.namesWanted + 1] = tonumber(id)
      end
    end
  end

  if count == 0 then return nil, "no_items" end
  return result
end
