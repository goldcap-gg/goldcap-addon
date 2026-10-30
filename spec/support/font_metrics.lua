-- Text widths measured in a TrueType face on disk, so a layout spec can check a label against the
-- face the addon really draws it in rather than against a guess per character. Reads the glyph
-- advances ('hmtx', 'hhea'), the units per em ('head') and the Windows Unicode map ('cmap'
-- platform 3, encoding 1, format 4, the one GoldCap's bundled faces carry). Kerning is left out:
-- these faces keep it only in GPOS. Pure Lua, byte arithmetic only, so it runs on any Lua the
-- suite runs on.
local Font = {}
Font.__index = Font

local function u16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  return a * 256 + b
end

local function s16(data, at)
  local v = u16(data, at)
  return v >= 32768 and v - 65536 or v
end

local function u32(data, at)
  return u16(data, at) * 65536 + u16(data, at + 2)
end

local function tables(data)
  local found = {}
  for i = 0, u16(data, 4) - 1 do
    local record = 12 + 16 * i
    found[data:sub(record + 1, record + 4)] = u32(data, record + 8)
  end
  return found
end

local function bmpMap(data, cmap)
  for i = 0, u16(data, cmap + 2) - 1 do
    local record = cmap + 4 + 8 * i
    local platform, encoding = u16(data, record), u16(data, record + 2)
    local sub = cmap + u32(data, record + 4)
    if platform == 3 and encoding == 1 and u16(data, sub) == 4 then return sub end
  end
  error("no format 4 Windows Unicode cmap")
end

function Font.load(path)
  local file = assert(io.open(path, "rb"))
  local data = file:read("*a")
  file:close()
  local at = tables(data)
  assert(at["head"] and at["hhea"] and at["hmtx"] and at["cmap"], path .. " is missing a table")
  return setmetatable({
    data = data,
    unitsPerEm = u16(data, at["head"] + 18),
    metrics = u16(data, at["hhea"] + 34),
    hmtx = at["hmtx"],
    map = bmpMap(data, at["cmap"]),
  }, Font)
end

-- The glyph for a code point, 0 when the face has none.
function Font:glyph(code)
  local data, sub = self.data, self.map
  if code > 0xFFFF then return 0 end
  local segments = u16(data, sub + 6) / 2
  local ends, starts = sub + 14, sub + 16 + 2 * segments
  local deltas, offsets = starts + 2 * segments, starts + 4 * segments
  for i = 0, segments - 1 do
    if u16(data, ends + 2 * i) >= code then
      local first = u16(data, starts + 2 * i)
      if first > code then return 0 end
      local delta, offset = s16(data, deltas + 2 * i), u16(data, offsets + 2 * i)
      if offset == 0 then return (code + delta) % 65536 end
      local glyph = u16(data, offsets + 2 * i + offset + 2 * (code - first))
      return glyph == 0 and 0 or (glyph + delta) % 65536
    end
  end
  return 0
end

function Font:advance(glyph)
  local index = glyph < self.metrics and glyph or self.metrics - 1
  return u16(self.data, self.hmtx + 4 * index)
end

local function codepoints(text)
  local codes, i = {}, 1
  while i <= #text do
    local byte = text:byte(i)
    local size = (byte < 0x80 and 1) or (byte < 0xE0 and 2) or (byte < 0xF0 and 3) or 4
    local code = byte
    if size == 2 then code = (byte - 0xC0) * 64 + (text:byte(i + 1) - 0x80)
    elseif size == 3 then
      code = (byte - 0xE0) * 4096 + (text:byte(i + 1) - 0x80) * 64 + (text:byte(i + 2) - 0x80)
    elseif size == 4 then
      code = (byte - 0xF0) * 262144 + (text:byte(i + 1) - 0x80) * 4096
        + (text:byte(i + 2) - 0x80) * 64 + (text:byte(i + 3) - 0x80)
    end
    codes[#codes + 1] = code
    i = i + size
  end
  return codes
end

-- The width of `text` at `pixels` per em. A character this face has no glyph for counts as
-- `missingEm` ems (1 when not given): Korean and Chinese draw in the client's own face, where a
-- Hangul or Han glyph is a full em wide.
function Font:width(text, pixels, missingEm)
  local units = 0
  for _, code in ipairs(codepoints(text)) do
    local glyph = self:glyph(code)
    if glyph == 0 then
      units = units + (missingEm or 1) * self.unitsPerEm
    else
      units = units + self:advance(glyph)
    end
  end
  return units * pixels / self.unitsPerEm
end

return Font
