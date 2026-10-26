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
  table.sort(out, function(a, b)
    if a.seen ~= b.seen then return a.seen > b.seen end
    return a.full < b.full
  end)
  return out
end

--- A typed "Name" or "Name-Realm" as "Name-Realm": the first letter upper case, the rest as typed,
--- a realm with spaces losing them, and a name with no realm on `me`'s. Nil for an empty name, a
--- name with a space in it, or a "-" with a realm missing.
function M.Full(typed, me)
  if type(typed) ~= "string" or type(me) ~= "table" then return nil end
  local name, dash, realm = typed:match("^%s*([^-]*)(-?)(.*)$")
  realm = realm:gsub("%s+", "")
  if name == "" or name:find("%s") then return nil end
  if dash == "" then realm = me.realm end
  if not text(realm) then return nil end
  return key(name:sub(1, 1):upper() .. name:sub(2), realm)
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
