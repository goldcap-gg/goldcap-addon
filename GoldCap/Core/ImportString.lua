local _, GC = ...

GC.ImportString = { MAX_LEN = 60000, REGION_MAX_LEN = 6000000 }

-- The one list of regions this addon understands, shared with Core/Data.lua's region
-- detection. Mirrors regionSchema in packages/schema (us/eu/kr/tw): the server has
-- emitted kr and tw import strings ever since those regions started ingesting, and
-- the companion app has known them for as long -- this list refusing them was the
-- only reason those two regions never worked.
GC.ImportString.REGIONS = { us = true, eu = true, kr = true, tw = true }

-- Section readers, shared by Parse (GCS1) and ParseRegion (GCM1): one grammar per section
-- letter, whichever wire carries it. Each fills `into` and returns how many entries it read.

-- I: the 4th field (trend) is a signed 24h market-value momentum percent; it only ever rides
-- alongside a sold figure (see itemToken's comment in packages/tsm), so a bare "id=mv" or
-- "id=mv=sold" token still parses identically to before this field existed.
local function readItems(body, into)
  local n = 0
  for id, mv, sold, trend in body:gmatch("(%d+)=(%d+)=?([%d%.]*)=?(%-?%d*)") do
    local entry = { m = tonumber(mv) }
    if sold ~= "" then entry.s = tonumber(sold) end
    if trend ~= "" then entry.t = tonumber(trend) end
    into[tonumber(id)] = entry
    n = n + 1
  end
  return n
end

-- I, as GCM1 reads it: the same three token shapes the site writes (id=mv, id=mv=sold,
-- id=mv=sold=trend), each token matched whole. readItems' pattern is unanchored, so on a digit
-- run with no "=" it restarts at every position and backtracks through the rest of the run:
-- quadratic, which Parse's 60,000-character cap keeps to seconds and the payload's 6,000,000
-- would turn into hours of a frozen load. Here every pattern is anchored and no two adjacent
-- captures can take the same characters, so a token costs one scan, and a malformed one drops
-- itself -- and stays out of counts.items -- like a malformed V, Q, R or M token does. readItems
-- itself stays as it is: GCS1 is frozen, and so is what Parse reads.
local function readItemTokens(body, into)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local id, mv, tail = token:match("^(%d+)=(%d+)(.*)$")
    local sold, trend
    if id and tail ~= "" then
      sold, trend = tail:match("^=([%d%.]+)=(%-?%d+)$")
      if not sold then sold = tail:match("^=([%d%.]+)$") end
      if not sold then id = nil end
    end
    if id then
      local entry = { m = tonumber(mv) }
      if sold then entry.s = tonumber(sold) end
      if trend then entry.t = tonumber(trend) end
      into[tonumber(id)] = entry
      n = n + 1
    end
  end
  return n
end

-- V: verification tokens are deliberately independent from I tokens. A malformed safety record
-- must not hide its matching market value: it simply leaves that item unverified.
local function readFacts(body, into)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local id, sourceAt, stressUnit, sellThroughBps, liquidityConfidence, currentQty,
        listings, observations, madBps, flags = token:match(
          "^(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)$")
    if id then
      into[tonumber(id)] = {
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
      n = n + 1
    end
  end
  return n
end

-- Q (p25 over listings) and R (reach24), copper per commodity: the Sell tab's ceilings for
-- posting above the cheapest ask (Flips.RecommendPost) -- R first, Q the fallback. Anchored per
-- token, a malformed token dropping itself and nothing else; sections of their own because the
-- I parser above is not anchored, and builds that predate them skip unknown sections cleanly.
-- Optional in both directions: a site build that predates R emits none and the Sell tab falls
-- back to Q.
local function readPrices(body, into)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local id, copper = token:match("^(%d+)=(%d+)$")
    if id then
      into[tonumber(id)] = tonumber(copper)
      n = n + 1
    end
  end
  return n
end

-- T: region reference price per REALM item (copper), plus the item level of the variant it was
-- measured on (0 when unknown or when the item has no item level at all). Realm items only: a
-- commodity carries a V fact instead, and the server excludes commodities here. What lets the
-- key poll (Core/KeyPoll.lua) judge gear, pets and recipes against something other than this
-- one realm's own median -- see Core/Trigger.lua's ForRealm. Anchored per token exactly like Q
-- and R.
local function readTargets(body, into)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local id, ref, ilvl = token:match("^(%d+)=(%d+)=(%d+)$")
    if id then
      into[tonumber(id)] = { ref = tonumber(ref), ilvl = tonumber(ilvl) }
      n = n + 1
    end
  end
  return n
end

-- M (GCM1 only): a realm item's region median and the listings it was measured over -- the
-- tooltip role the bundled table's realm entries play (`m`, `l`), from this hour instead of
-- release day. Anchored per token like Q, R and T. Two flat maps, id -> median and id -> listings:
-- a { m, l } table per item held twice the memory for a region's tens of thousands of them.
local function readRefs(body, medians, listingsInto)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local id, median, listings = token:match("^(%d+)=(%d+)=(%d+)$")
    if id then
      id = tonumber(id)
      medians[id] = tonumber(median)
      listingsInto[id] = tonumber(listings)
      n = n + 1
    end
  end
  return n
end

-- F (GCM1 only): a realm item that trades, `itemId=refCopper=sales7d=saleRealms7d`. refCopper is
-- the median price per unit it SOLD for over the last 7 days across the region's realms (the
-- site's realm sales tape), with the sales and realms behind it. All four positive. Anchored per
-- token like M: a malformed token drops itself and is not counted.
local function readFlips(body, into)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local id, ref, sales, realms = token:match("^(%d+)=(%d+)=(%d+)=(%d+)$")
    id, ref, sales, realms = tonumber(id), tonumber(ref), tonumber(sales), tonumber(realms)
    if id and id > 0 and ref > 0 and sales > 0 and realms > 0 then
      into[id] = { ref = ref, sales7d = sales, realms = realms }
      n = n + 1
    end
  end
  return n
end

-- U (GCM1 only): a rare find, listed on many realms and rarely sold, which the site gives no price.
-- `itemId=sales30d=lastSaleCopper=lastSoldAgeHours=realmsListed=floorMin=floorP10=floorP25`: the
-- sales seen in 30 days, the last one's price per unit and its age in whole hours before the
-- payload's ts (0 and 0 when there was none), then how many realms list it and the min, 10th and
-- 25th percentile of those realms' cheapest listings. All whole; the id, the realm count and the
-- three floors positive. Anchored per token like F.
local function readRares(body, into)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local f = { token:match("^(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)=(%d+)$") }
    for i = 1, #f do f[i] = tonumber(f[i]) end
    local id = f[1]
    if id and id > 0 and f[5] > 0 and f[6] > 0 and f[7] > 0 and f[8] > 0 then
      into[id] = { sales30d = f[2], lastSaleCopper = f[3], lastSoldAgeHours = f[4], realmsListed = f[5],
        floorMin = f[6], floorP10 = f[7], floorP25 = f[8] }
      n = n + 1
    end
  end
  return n
end

-- L (GCM1 only): the item level a flip was priced at, `itemId=ilvl`, only for the flips that name
-- one (armor and weapons, priced at the level that sold most). A section of its own rather than a
-- fifth F field: readFlips above is anchored at four, and a fifth would have dropped every flip in
-- the builds already installed. Both positive.
local function readLevels(body, into)
  for token in body:gmatch("[^,]+") do
    local id, ilvl = token:match("^(%d+)=(%d+)$")
    id, ilvl = tonumber(id), tonumber(ilvl)
    if id and id > 0 and ilvl > 0 then into[id] = ilvl end
  end
end

-- C (GCM1 only): a connected realm of the region, `realmId=Display Name=key|key|...`: the name to
-- show, then every name the client may print for any of its member realms, keyed the way
-- GC.SellRoute.Key keys GetRealmName(). Two flat maps, id -> name and key -> id. A realm name holds
-- none of , ; = | and the site refuses one that would.
local function readRealms(body, names, keys)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local id, name, keyList = token:match("^(%d+)=([^=]+)=([^=]+)$")
    id = tonumber(id)
    if id and id > 0 then
      names[id] = name
      for key in keyList:gmatch("[^|]+") do keys[key] = id end
      n = n + 1
    end
  end
  return n
end

-- S (GCM1 only): a realm a flip sells on within a week, `itemId=realmId=listCopper=daysTenths=own`:
-- what to list it at there, tenths of a day until it sells, and 1 when that realm's own sales
-- priced it (else the region's price and the realm's appetite did). An item's tokens come best net
-- first and stay in that order. All positive, own 0 or 1. Counts the items, not the tokens.
local function readSpots(body, into)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local id, realm, list, tenths, own = token:match("^(%d+)=(%d+)=(%d+)=(%d+)=([01])$")
    id, realm, list, tenths = tonumber(id), tonumber(realm), tonumber(list), tonumber(tenths)
    if id and id > 0 and realm > 0 and list > 0 and tenths > 0 then
      local spots = into[id]
      if not spots then
        spots = {}
        into[id] = spots
        n = n + 1
      end
      spots[#spots + 1] = { realmId = realm, list = list, days = tenths / 10, own = own == "1" }
    end
  end
  return n
end

-- K (GCM1 only): a flip's fifth cheapest realm floor at its priced level, and over how many realms,
-- `itemId=floor5thCopper=realmsListed`. A realm whose cheapest listing is at or under it is among
-- the five cheapest to buy on. All positive.
local function readCheap(body, into)
  for token in body:gmatch("[^,]+") do
    local id, floor5th, realms = token:match("^(%d+)=(%d+)=(%d+)$")
    id, floor5th, realms = tonumber(id), tonumber(floor5th), tonumber(realms)
    if id and id > 0 and floor5th > 0 and realms > 0 then
      into[id] = { floor5th = floor5th, realms = realms }
    end
  end
end

-- W (site watchlist) and N (item ids the site has no name for -- Blizzard's API 404s them;
-- Core/ItemNames.lua resolves them from the client and the Companion reports the names back):
-- plain id lists, in order.
local function readIds(body, into)
  for id in body:gmatch("%d+") do
    into[#into + 1] = tonumber(id)
  end
end

function GC.ImportString.Parse(str)
  if type(str) ~= "string" then return nil, "empty" end
  if #str > GC.ImportString.MAX_LEN then return nil, "too_long" end
  str = str:gsub("%s+", "")
  if #str == 0 then return nil, "empty" end
  -- Browsers copying a text/plain response often prepend an invisible byte
  -- (UTF-8 BOM, zero-width space) that gsub("%s+") does not strip; drop any
  -- leading junk before the GCS1 marker so a clean paste isn't rejected.
  str = str:match("GCS1;.*") or str
  -- Two strings pasted one after the other. The match above starts at the FIRST marker and
  -- runs to the end of the paste, so the second string's sections are read as if they were
  -- the first string's -- one realm's prices silently overwriting another's under the first
  -- realm's name. Refuse the pair instead of merging them.
  if str:find("GCS1;", 2, true) then return nil, "two_strings" end

  -- The realm is a LABEL: it is stored, printed back in /goldcap status and never parsed.
  -- Matching it as "lowercase letters, digits and hyphens" therefore bought nothing and cost
  -- every Korean and Taiwanese player their import -- Blizzard's own realm slugs there are
  -- not ASCII, so a perfectly good string came back as "that does not look like a GoldCap
  -- import string", the one message that sends a player hunting for a broken copy-paste.
  -- Anything that is not the field separator is a realm now; only an empty one is an error,
  -- and it says so in its own words.
  local region, realm, ts, rest =
    str:match("^GCS1;(%l%l);([^;]*);(%d+);(.+)$")
  if not region then return nil, "bad_header" end
  if realm == "" then return nil, "no_realm" end
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
      count = count + readItems(body, result.items)
    elseif kind == "V" then
      readFacts(body, result.verification)
    elseif kind == "Q" then
      readPrices(body, result.quarter)
    elseif kind == "R" then
      readPrices(body, result.reach)
    elseif kind == "T" then
      readTargets(body, result.targets)
    elseif kind == "W" then
      readIds(body, result.watchlist)
    elseif kind == "N" then
      readIds(body, result.namesWanted)
    end
  end

  if count == 0 then return nil, "no_items" end
  return result
end

-- GCM1: the whole commodity market of one region, which the Companion writes beside the import
-- string as GoldCap_AppData.regionString (GET /v1/addon/region-data). Never pasted, so none of
-- Parse's paste repairs apply; its own limit, a hundred times the import string's, because it
-- carries every commodity instead of the busiest 400. `counts` is what /goldcap status prints
-- without walking the tables again.
function GC.ImportString.ParseRegion(str)
  if type(str) ~= "string" then return nil, "empty" end
  if #str > GC.ImportString.REGION_MAX_LEN then return nil, "too_long" end
  -- Trailing whitespace goes: every reader below is anchored per token, so a newline a producer
  -- someday ends the payload with would otherwise cost the last section its last token, without
  -- a word. Walked back byte by byte (space, \t \n \v \f \r -- %s in the C locale): a `%s+$`
  -- gsub retries from every position of a whitespace run, quadratic on a long one.
  local last = #str
  while last > 0 do
    local b = str:byte(last)
    if b ~= 32 and (b < 9 or b > 13) then break end
    last = last - 1
  end
  if last == 0 then return nil, "empty" end
  if last < #str then str = str:sub(1, last) end
  local region, ts, rest = str:match("^GCM1;(%l%l);(%d+);(.*)$")
  if not region then return nil, "bad_header" end
  if not GC.ImportString.REGIONS[region] then return nil, "bad_region" end

  local result = {
    region = region, ts = tonumber(ts),
    items = {}, verification = {}, quarter = {}, reach = {}, refs = {}, refListings = {},
    counts = { items = 0, facts = 0, refs = 0 },
  }
  for section in rest:gmatch("[^;]+") do
    local kind, body = section:match("^(%u):(.+)$")
    if kind == "I" then
      result.counts.items = result.counts.items + readItemTokens(body, result.items)
    elseif kind == "V" then
      result.counts.facts = result.counts.facts + readFacts(body, result.verification)
    elseif kind == "Q" then
      readPrices(body, result.quarter)
    elseif kind == "R" then
      readPrices(body, result.reach)
    elseif kind == "M" then
      result.counts.refs = result.counts.refs + readRefs(body, result.refs, result.refListings)
    -- F and U only once the site's realm sales tape covers a week of the region. Until then a
    -- payload carries neither, and its result has neither table nor count: it parses exactly as a
    -- payload did before the sections existed.
    elseif kind == "F" then
      result.flips = result.flips or {}
      result.counts.flips = (result.counts.flips or 0) + readFlips(body, result.flips)
    elseif kind == "U" then
      result.rares = result.rares or {}
      result.counts.rares = (result.counts.rares or 0) + readRares(body, result.rares)
    -- L, C, S and K the same way: only once the site works out where each flip sells. A payload
    -- without them has none of their tables or counts.
    elseif kind == "L" then
      result.flipLevels = result.flipLevels or {}
      readLevels(body, result.flipLevels)
    elseif kind == "C" then
      result.realms, result.realmKeys = result.realms or {}, result.realmKeys or {}
      result.counts.realms = (result.counts.realms or 0) + readRealms(body, result.realms, result.realmKeys)
    elseif kind == "S" then
      result.spots = result.spots or {}
      result.counts.routes = (result.counts.routes or 0) + readSpots(body, result.spots)
    elseif kind == "K" then
      result.cheap = result.cheap or {}
      readCheap(body, result.cheap)
    end
  end

  if result.counts.items == 0 then return nil, "no_items" end
  return result
end

-- WoW: Forever: every player's scans for one market, as the Companion writes it into the Forever
-- install's GoldCap_AppData.foreverString. The site's grammar (plan 2a, Task 9):
--   GCF1;<slug>;<regionId>;<realm>;<faction or ->;<ts>;I:<id>=<min>=<ah>=<mv>=<p50>=<qty>=<scanners>=<age>[=g],...
-- The realm has % ; , = : | percent-escaped. mv and p50 may be empty. age is minutes before ts.
-- Every token is matched whole and anchored: a malformed one drops itself, never the payload.
GC.ImportString.FOREVER_MAX_LEN = 2000000

local function unescapeField(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function GC.ImportString.ParseForever(str)
  if type(str) ~= "string" then return nil, "empty" end
  if #str > GC.ImportString.FOREVER_MAX_LEN then return nil, "too_long" end
  local slug, regionId, realm, faction, ts, rest = str:match("^GCF1;([%l%d%-]+);(%d+);([^;]*);([^;]*);(%d+);(.*)$")
  if not slug then return nil, "bad_header" end
  local result = { slug = slug, regionId = tonumber(regionId), realm = unescapeField(realm),
    faction = faction ~= "-" and faction ~= "" and faction or nil, ts = tonumber(ts), items = {}, count = 0 }
  for section in rest:gmatch("[^;]+") do
    local kind, body = section:match("^(%u):(.*)$")
    if kind == "I" then
      for token in body:gmatch("[^,]+") do
        local id, min, ah, mv, p50, qty, w, age, g =
          token:match("^(%d+)=(%d+)=(%d+)=(%d*)=(%d*)=(%d+)=(%d+)=(%d+)=?(g?)$")
        if id then
          result.items[tonumber(id)] = { min = tonumber(min), ah = tonumber(ah), mv = tonumber(mv),
            p50 = tonumber(p50), qty = tonumber(qty), w = tonumber(w), age = tonumber(age),
            gear = g == "g" or nil }
          result.count = result.count + 1
        end
      end
    end
  end
  if result.count == 0 then return nil, "no_items" end
  return result
end
