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
    items = {}, verification = {}, quarter = {}, reach = {}, targets = {},
    watchlist = {}, namesWanted = {},
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
    elseif kind == "Q" then
      -- Top of the cheap quarter (p25 over listings, copper), commodities only -- the
      -- FALLBACK ceiling for posting above the cheapest ask, used only when the R section
      -- below carries no reach figure for the item (Flips.RecommendPost, overcut). Anchored
      -- per token like V: a malformed token drops itself and nothing else. It is a section
      -- rather than a fifth I field because the I parser above is not anchored, and builds
      -- that predate this one skip unknown sections cleanly.
      for token in body:gmatch("[^,]+") do
        local id, p25 = token:match("^(%d+)=(%d+)$")
        if id then result.quarter[tonumber(id)] = tonumber(p25) end
      end
    elseif kind == "R" then
      -- reach24 (copper), commodities only: the price this item's floor actually rose to
      -- within a day, measured from its own hourly history. It replaces Q as the ceiling for
      -- posting above the cheapest ask (Flips.RecommendPost) -- see that file's own header for
      -- why a rank in today's book was the wrong ceiling. Anchored per token exactly like Q, a
      -- malformed token dropping itself and nothing else, and optional in both directions: a
      -- site build that predates it emits no R section and the Sell tab falls back to Q, while
      -- an addon build that predates it skips the section as an unknown one.
      for token in body:gmatch("[^,]+") do
        local id, reach = token:match("^(%d+)=(%d+)$")
        if id then result.reach[tonumber(id)] = tonumber(reach) end
      end
    elseif kind == "T" then
      -- Region reference price per REALM item (copper), plus the item level of the variant it
      -- was measured on (0 when unknown or when the item has no item level at all). Realm
      -- items only: a commodity carries a V section instead, and the server excludes them
      -- here. This is what lets the key poll (Core/KeyPoll.lua) judge gear, pets and recipes
      -- against something other than this one realm's own median -- see Core/Trigger.lua's
      -- ForRealm. Anchored per token exactly like Q and R, so a malformed token drops itself
      -- and nothing else, and optional in both directions: a site build that predates the
      -- section emits none, and a build that predates this parser skips it as unknown.
      for token in body:gmatch("[^,]+") do
        local id, ref, ilvl = token:match("^(%d+)=(%d+)=(%d+)$")
        if id then result.targets[tonumber(id)] = { ref = tonumber(ref), ilvl = tonumber(ilvl) } end
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
