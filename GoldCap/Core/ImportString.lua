local _, GC = ...

GC.ImportString = { MAX_LEN = 60000 }

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
  if region ~= "eu" and region ~= "us" then return nil, "bad_header" end

  local result = {
    region = region, realm = realm, ts = tonumber(ts),
    items = {}, watchlist = {},
  }
  local count = 0

  for section in rest:gmatch("[^;]+") do
    local kind, body = section:match("^(%u):(.+)$")
    if kind == "I" then
      for id, mv, sold in body:gmatch("(%d+)=(%d+)=?([%d%.]*)") do
        local entry = { m = tonumber(mv) }
        if sold ~= "" then entry.s = tonumber(sold) end
        result.items[tonumber(id)] = entry
        count = count + 1
      end
    elseif kind == "W" then
      for id in body:gmatch("%d+") do
        result.watchlist[#result.watchlist + 1] = tonumber(id)
      end
    end
  end

  if count == 0 then return nil, "no_items" end
  return result
end
