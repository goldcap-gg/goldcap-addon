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
-- release day. Anchored per token like Q, R and T.
local function readRefs(body, into)
  local n = 0
  for token in body:gmatch("[^,]+") do
    local id, median, listings = token:match("^(%d+)=(%d+)=(%d+)$")
    if id then
      into[tonumber(id)] = { m = tonumber(median), l = tonumber(listings) }
      n = n + 1
    end
  end
  return n
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
    items = {}, verification = {}, quarter = {}, reach = {}, refs = {},
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
      result.counts.refs = result.counts.refs + readRefs(body, result.refs)
    end
  end

  if result.counts.items == 0 then return nil, "no_items" end
  return result
end
