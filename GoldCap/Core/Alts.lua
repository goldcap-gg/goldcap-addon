local _, GC = ...

-- The player's characters (retail only): which characters this account has played, remembered as
-- each one logs in or levels up, and which of them this character can mail. Pure apart from the
-- event frame at the end: the functions take the SavedVariables table, the current character and
-- the connected realms as plain values. GoldCap_Camelot.toc does not load this file.
--
-- Characters are saved in GC.db.alts = { v = 1, chars = { ["Name-Realm"] = { name, realm, class,
-- level, faction, seen } } }, account-wide, created lazily with the first record and not through
-- DEFAULTS, so a client that never loads this file keeps its SavedVariables as they were. The
-- realm is the normalized one (GetNormalizedRealmName: no spaces), the class the file token and
-- `seen` the time of the last login or level up. A save with a newer `v` is read-only.
GC.Alts = {}
local M = GC.Alts

M.VERSION = 1
-- How long a character may go unseen before mail to it is asked about again (Recent): one deleted
-- or renamed since may have had its name taken by someone else.
M.RECENT = 30 * 86400

local function newer(saved)
  return type(saved) == "table" and type(saved.v) == "number" and saved.v > M.VERSION
end

local function ours(saved)
  return type(saved) == "table" and saved.v == M.VERSION and type(saved.chars) == "table"
end

local function key(name, realm)
  return name .. "-" .. realm
end

local function text(s)
  return type(s) == "string" and s ~= ""
end

--- Remembers the character `me` = { name, realm, class, level, faction } as seen at time `now`,
--- replacing what was saved for it. Creates the table with the first record; a character with a
--- field missing is not recorded, and a newer GoldCap's table is left as it is.
function M.Record(db, me, now)
  if type(db) ~= "table" or type(me) ~= "table" or newer(db.alts) then return end
  if not (text(me.name) and text(me.realm) and text(me.class) and text(me.faction)) then return end
  if type(me.level) ~= "number" or type(now) ~= "number" then return end
  if not ours(db.alts) then db.alts = { v = M.VERSION, chars = {} } end
  db.alts.chars[key(me.name, me.realm)] = {
    name = me.name, realm = me.realm, class = me.class, level = me.level, faction = me.faction, seen = now,
  }
end

--- Whether `full` ("Name-Realm") is a recorded character.
function M.IsMine(db, full)
  local saved = type(db) == "table" and db.alts or nil
  return ours(saved) and saved.chars[full] ~= nil or false
end

--- Whether `full` is a recorded character seen within RECENT of `now`. False for one not seen for
--- longer, one saved with no `seen`, and a name that is not recorded.
function M.Recent(db, full, now)
  local saved = type(db) == "table" and db.alts or nil
  local c = ours(saved) and saved.chars[full] or nil
  if type(c) ~= "table" or type(c.seen) ~= "number" or type(now) ~= "number" then return false end
  return now - c.seen <= M.RECENT
end

local function connectedTo(realm, me, connected)
  if realm == me.realm then return true end
  if type(connected) == "table" then
    for _, r in ipairs(connected) do
      if r == realm then return true end
    end
  end
  return false
end

local function mailNameOf(name, realm, me)
  return realm == me.realm and name or key(name, realm)
end

--- The name to type in a mail's To field for `full`, or nil when this character cannot mail it:
--- itself, or a character of a realm that is neither this one nor in `connected` (the list
--- GetAutoCompleteRealms answers, nil or empty meaning this realm only).
function M.MailName(full, me, connected)
  if type(full) ~= "string" or type(me) ~= "table" then return nil end
  local name, realm = full:match("^([^-]+)-(.+)$")
  if not name or full == key(me.name, me.realm) or not connectedTo(realm, me, connected) then return nil end
  return mailNameOf(name, realm, me)
end

--- The characters `me` can mail, newest seen first and then by name: those of its faction on its
--- realm or a connected one, never itself. Each is { full, name, realm, class, level, seen,
--- mailName }, mailName being what MailName answers.
function M.Recipients(db, me, connected)
  local out = {}
  local saved = type(db) == "table" and db.alts or nil
  if not ours(saved) or type(me) ~= "table" then return out end
  local mine = key(me.name, me.realm)
  for full, c in pairs(saved.chars) do
    if full ~= mine and c.faction == me.faction and connectedTo(c.realm, me, connected) then
      out[#out + 1] = {
        full = full, name = c.name, realm = c.realm, class = c.class, level = c.level, seen = c.seen,
        mailName = mailNameOf(c.name, c.realm, me),
      }
    end
  end
  -- A save with no `seen` (written by hand, or by another tool) sorts as never seen.
  table.sort(out, function(a, b)
    local as, bs = tonumber(a.seen) or 0, tonumber(b.seen) or 0
    if as ~= bs then return as > bs end
    return a.full < b.full
  end)
  return out
end

-- Upper and lower case for the letters of the realms GoldCap's languages play on, as code points:
-- ASCII; Latin-1 Supplement (U+00C0 to U+00DE and U+0020 above, but × and ÷); Latin Extended-A,
-- whose pairs are an upper case even and its lower case odd, but from U+0139 to U+0148 and U+0179
-- to U+017E the other way round (ı, İ, ĸ, ŉ, ſ have no pair there); and Cyrillic (U+0410 to U+042F
-- and U+0020 above, U+0400 to U+040F and U+0050 above, and the pairs from U+0490, Ukrainian Ґ, to
-- U+04BF, upper even). Lua's own upper and lower stop at ASCII. The client documents C_Intl.ToLower
-- and ToUpper in both games, locale-dependent and allowed to return nothing, and nothing measured
-- them; a name compared on one character and typed on another must fold the same way, so this
-- table is the one rule.
local EVEN_UPPER = { { 0x0100, 0x012F }, { 0x0132, 0x0137 }, { 0x014A, 0x0177 }, { 0x0490, 0x04BF } }
local ODD_UPPER = { { 0x0139, 0x0148 }, { 0x0179, 0x017E } }

local function within(code, ranges)
  for _, r in ipairs(ranges) do
    if code >= r[1] and code <= r[2] then return true end
  end
  return false
end

local function lowerCode(code)
  if (code >= 0x41 and code <= 0x5A) or (code >= 0xC0 and code <= 0xDE and code ~= 0xD7)
    or (code >= 0x0410 and code <= 0x042F) then
    return code + 0x20
  end
  if code >= 0x0400 and code <= 0x040F then return code + 0x50 end
  if (within(code, EVEN_UPPER) and code % 2 == 0) or (within(code, ODD_UPPER) and code % 2 == 1) then
    return code + 1
  end
  return code
end

local function upperCode(code)
  if (code >= 0x61 and code <= 0x7A) or (code >= 0xE0 and code <= 0xFE and code ~= 0xF7)
    or (code >= 0x0430 and code <= 0x044F) then
    return code - 0x20
  end
  if code >= 0x0450 and code <= 0x045F then return code - 0x50 end
  if (within(code, EVEN_UPPER) and code % 2 == 1) or (within(code, ODD_UPPER) and code % 2 == 0) then
    return code - 1
  end
  return code
end

-- One UTF-8 character.
local CHAR = "[%z\1-\127\192-\255][\128-\191]*"

-- `s` with each character of one or two bytes put through `map` on its code point; longer ones
-- (no case among them here) as they are.
local function mapChars(s, map)
  return (s:gsub(CHAR, function(ch)
    local b1, b2 = ch:byte(1, 2)
    local code
    if #ch == 1 then
      code = b1
    elseif #ch == 2 then
      code = (b1 - 0xC0) * 64 + (b2 - 0x80)
    else
      return ch
    end
    local mapped = map(code)
    if mapped == code then return ch end
    if mapped < 0x80 then return string.char(mapped) end
    return string.char(0xC0 + math.floor(mapped / 64), 0x80 + mapped % 64)
  end))
end

--- `s` in lower case, for comparing names whatever case they were typed in.
function M.Lower(s)
  return mapChars(s, lowerCode)
end

--- `s` with its first letter in upper case and the rest as it is.
function M.UpperFirst(s)
  local first, rest = s:match("^(" .. CHAR .. ")(.*)$")
  if not first then return s end
  return mapChars(first, upperCode) .. rest
end

-- A realm as typed or listed, for comparing: lower case, without spaces, hyphens or apostrophes
-- (the client's own names drop spaces, "Azjol-Nerub" is AzjolNerub, and Mal'Ganis keeps its own).
local function realmKey(realm)
  return (M.Lower(realm):gsub("[%s%-']", ""):gsub("\226\128\153", ""))
end

-- The realm `typed` names among `me`'s and `connected`, in their spelling; else as typed.
local function listedRealm(typed, me, connected)
  local want = realmKey(typed)
  if want == "" then return typed end
  if realmKey(me.realm) == want then return me.realm end
  if type(connected) == "table" then
    for _, r in ipairs(connected) do
      if type(r) == "string" and realmKey(r) == want then return r end
    end
  end
  return typed
end

-- The recorded character `name` on `realm`, whatever the case of either, as recorded; or nil.
local function recorded(db, name, realm)
  local saved = type(db) == "table" and db.alts or nil
  if not ours(saved) then return nil end
  local wantName, wantRealm = M.Lower(name), realmKey(realm)
  for _, c in pairs(saved.chars) do
    if type(c) == "table" and text(c.name) and text(c.realm) and M.Lower(c.name) == wantName
      and realmKey(c.realm) == wantRealm then
      return key(c.name, c.realm)
    end
  end
  return nil
end

--- A typed "Name" or "Name-Realm" as "Name-Realm". A name with no realm is on `me`'s; a typed realm
--- that is `me`'s or one in `connected` (whatever its case, spaces, hyphens or apostrophes) takes
--- the list's spelling, any other loses its spaces. One of the recorded characters in `db` (the
--- name in any case) is that character as recorded; any other name gets its first letter upper
--- case and the rest as typed. Nil for an empty name, a name with a space in it, or a "-" with a
--- realm missing.
function M.Full(db, typed, me, connected)
  if type(typed) ~= "string" or type(me) ~= "table" then return nil end
  local name, dash, realm = typed:match("^%s*([^-]*)(-?)(.*)$")
  realm = realm:gsub("%s+", "")
  if name == "" or name:find("%s") then return nil end
  if dash == "" then realm = me.realm else realm = listedRealm(realm, me, connected) end
  if not text(realm) then return nil end
  return recorded(db, name, realm) or key(M.UpperFirst(name), realm)
end

-- One guarded client read: its first value, or nil when the call is missing or fails.
local function read(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

--- What the event frame does at PLAYER_LOGIN and PLAYER_LEVEL_UP: reads the character and time
--- and records them. A read that fails leaves a field nil, which Record refuses.
function M.OnEvent()
  if not GC.db then return end
  local me = {
    name = read(UnitName, "player"),
    realm = read(GetNormalizedRealmName),
    class = read(function() return (select(2, UnitClass("player"))) end),
    level = read(UnitLevel, "player"),
    faction = read(UnitFactionGroup, "player"),
  }
  M.Record(GC.db, me, read(time))
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "PLAYER_LOGIN")
  pcall(events.RegisterEvent, events, "PLAYER_LEVEL_UP")
  events:SetScript("OnEvent", function() M.OnEvent() end)
  M._events = events
end
