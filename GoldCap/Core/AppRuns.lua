local _, GC = ...

-- Buy runs (Core/BuyRun.lua draws them; this module is where they come from). Two sources,
-- both landing in the same `GC.db.runs` table keyed by code:
--
--   "app"   -- the companion's Runs plan writes `GoldCap_AppRuns` to
--             Interface/AddOns/GoldCap_AppData/Runs.lua, adopted by Adopt() below the same
--             way Core/AppLedger.lua adopts `GoldCap_AppLedger`. Unlike that ledger summary
--             (memory only, since nothing there survives a session anyway), a run is useful
--             for as long as the player is still shopping it, so it is folded into the
--             persisted SavedVariables `db.runs` rather than kept in a module-local.
--   "paste" -- a `GCR1;...` string pasted into UI/ImportDialog.lua's box, parsed by
--             ImportString() below, for a player without the companion.
--
-- Adopt() replaces every "app" run wholesale on each call (the companion's file is a
-- snapshot of everything it currently knows, not a diff) but never touches a "paste" run --
-- those exist only because the companion did not provide them, so nothing it says can make
-- them stale.
GC.AppRuns = {}

local function num(v) return type(v) == "number" and v or nil end

-- The realm a hit was seen on (v3). A line bound to another realm is still a line -- the auction
-- house search simply finds nothing for it there -- so the pair is carried and the caller decides
-- what to say about it. Either half may be missing; neither half present is no realm at all.
local function copyRealm(raw)
  if type(raw) ~= "table" then return nil end
  local id = num(raw.id)
  local name = type(raw.n) == "string" and raw.n ~= "" and raw.n or nil
  if not (id or name) then return nil end
  return { id = id, n = name }
end

-- The recipe that crafts this line's item (v3): `r` the recipe id, `n` how many units one craft
-- yields, `c` what one craft's reagents cost at the region's prices when the run was fetched, and
-- `i` the reagents themselves. Copied FIELD BY FIELD, not referenced: the companion rewrites its
-- global wholesale on every sync, while a run in SavedVariables outlives it, and a stored run
-- that pointed into that table would change under the player. A recipe yielding nothing, or
-- naming no reagent, is dropped -- there is nothing the tab could do with it.
local function copyCraft(raw)
  if type(raw) ~= "table" then return nil end
  local craftedQty = num(raw.n)
  if not craftedQty or craftedQty <= 0 then return nil end
  local reagents = {}
  for _, entry in ipairs(type(raw.i) == "table" and raw.i or {}) do
    local id, qty = num(entry.i), num(entry.q)
    if id and qty and qty > 0 then
      reagents[#reagents + 1] = {
        i = id, q = qty, n = type(entry.n) == "string" and entry.n or nil,
        v = entry.v == true, u = num(entry.u), vu = num(entry.vu),
      }
    end
  end
  if #reagents == 0 then return nil end
  return { r = num(raw.r), n = craftedQty, c = num(raw.c) or 0, i = reagents }
end

local function copyLine(raw)
  if type(raw) ~= "table" then return nil end
  local i, q = num(raw.i), num(raw.q)
  if not (i and q) then return nil end
  return {
    i = i, q = q, v = raw.v == true, n = type(raw.n) == "string" and raw.n or nil,
    -- The v2 price fields: `u` the site's own reference price for a unit at the moment the run
    -- was fetched, `vu` what a vendor charges for one, `ch`/`cp` the hour of the day (UTC) the
    -- item is usually cheapest and by how much. Every one is optional -- a v1 file, or a v2 line
    -- the site could not price, simply carries nil and the tab behaves exactly as it did.
    u = num(raw.u), vu = num(raw.vu), ch = num(raw.ch), cp = num(raw.cp),
    -- The v3 fields: `cc` an absolute copper ceiling for one unit (an alert group's own target
    -- price, which is not a percentage of anything), `rl` the realm a hit is bound to, `cr` the
    -- recipe that crafts this item. Optional, like every price field above them.
    cc = num(raw.cc), rl = copyRealm(raw.rl), cr = copyCraft(raw.cr),
  }
end

-- One line per item id, quantities summed. A run is allowed to name the same reagent twice --
-- two recipes on one shopping list do it constantly -- but Core/BuyRun.lua keys its purchase
-- state by item id, so two lines of the same item share one `bought`: buying the first marked
-- the second done, and the second line's quantity could never be bought at all. Merging under-
-- buys nothing; it is the same total, asked for once. The FIRST line keeps the position, the
-- name and the vendor flag: a later duplicate must not be able to turn a line the player can
-- buy into a vendor stop they cannot.
local function mergeLines(rawLines)
  local lines, byItem = {}, {}
  for _, rawLine in ipairs(rawLines) do
    local line = copyLine(rawLine)
    if line then
      local seen = byItem[line.i]
      if seen then
        seen.q = seen.q + line.q
      else
        byItem[line.i] = line
        lines[#lines + 1] = line
      end
    end
  end
  return lines
end

local function copyRun(raw, origin)
  if type(raw) ~= "table" then return nil end
  if type(raw.code) ~= "string" or raw.code == "" then return nil end
  if type(raw.lines) ~= "table" then return nil end
  local lines = mergeLines(raw.lines)
  if #lines == 0 then return nil end
  return {
    code = raw.code,
    name = type(raw.name) == "string" and raw.name or nil,
    updatedAt = num(raw.updatedAt) or time(),
    lines = lines,
    origin = origin,
    -- v3 run fields. `k` marks a run that is an alert group's live hits rather than a saved
    -- list; `by` names the owner of a run the player follows; `src` is the plan it came from
    -- ("Cooking 1-100"). All three are the site's to set and the addon's to carry: the tab reads
    -- them, nothing here invents them.
    k = raw.k == "alert" and "alert" or nil,
    by = (type(raw.by) == "string" and raw.by ~= "") and raw.by or nil,
    src = (type(raw.src) == "string" and raw.src ~= "") and raw.src or nil,
  }
end

-- What the site changed about a run the addon already had, or nil when it changed nothing worth
-- saying. Both halves have to differ: `updatedAt` alone moves whenever the site touches the row,
-- and a line set alone cannot move without it. Lines are compared by item id AND quantity, so a
-- recompute that only moved a number is still a changed plan -- with nothing added or removed,
-- which is a shape the band has its own wording for.
--
-- An alert run's lines ARE the alert group's live hits, not a plan: they change on essentially
-- every sync by design, so a notice here would sit permanently on a run that has no plan behind
-- it. The band already has its own wording for an alert run (a hit count) -- see
-- UI/BuyFrame.lua -- so an alert group's hits arriving and expiring is not news for this notice.
local function noticeFor(old, new)
  if new.k == "alert" then return nil end
  if type(old) ~= "table" or (old.updatedAt or 0) == (new.updatedAt or 0) then return nil end
  local before, after = {}, {}
  for _, line in ipairs(old.lines or {}) do before[line.i] = line.q end
  for _, line in ipairs(new.lines or {}) do after[line.i] = line.q end
  local added, removed, changed = 0, 0, false
  for id, qty in pairs(after) do
    if before[id] == nil then
      added, changed = added + 1, true
    elseif before[id] ~= qty then
      changed = true
    end
  end
  for id in pairs(before) do
    if after[id] == nil then removed, changed = removed + 1, true end
  end
  if not changed then return nil end
  return { at = time(), added = added, removed = removed }
end

-- What this character bought against an alert group's hits, minus the hits that are gone. An
-- alert run's lines ARE the group's live hits: one that expired is gone for good, and a later
-- hit for the same item is a different lot at a different price, which starts from nothing
-- bought. Nothing else ever prunes `buyProgress` -- it is keyed by the run code, and an alert
-- group's code does not change -- so without this a hit that came back would arrive already
-- part bought, against gold spent days ago on a lot nobody can see any more. Every character's
-- copy goes together: the score is per character, the expiry is not.
--
-- A saved list is left alone. Its lines are a plan the site recomputes, not hits: a line that
-- went today is one the player may put back tomorrow, and the run's score is still the run's.
local function pruneAlertProgress(db, run)
  if run.k ~= "alert" or type(db.buyProgress) ~= "table" then return end
  local live = {}
  for _, line in ipairs(run.lines) do live[line.i] = true end
  for _, byChar in pairs(db.buyProgress) do
    local forRun = type(byChar) == "table" and byChar[run.code] or nil
    if type(forRun) == "table" then
      for itemID in pairs(forRun) do
        if not live[itemID] then forRun[itemID] = nil end
      end
    end
  end
end

-- Reads `_G.GoldCap_AppRuns` (see this file's header for the shape and where it comes from)
-- and, when it is both well-formed and strictly newer than what is already stored, replaces
-- every "app" run in `GC.db.runs` with the ones it carries and stamps `GC.db.runsMeta`.
-- Anything malformed -- a bad version, a run with no code, a line with no item id -- is
-- dropped silently rather than repaired: same contract as AppLedger.Adopt, because the
-- companion is optional and a partly-broken write should not block the parts that are fine.
-- Returns whether it actually adopted anything, so a caller (none yet; kept for parity with
-- the interface and for a future "companion synced" toast) can tell a no-op from a real sync.
function GC.AppRuns.Adopt()
  local raw = _G.GoldCap_AppRuns
  -- v1, v2 and v3 are the same file; v2 lines carry prices and v3 lines carry a cap, a realm and
  -- a recipe (see copyLine). An unknown version is refused rather than half-read: a field this
  -- build does not know the meaning of is not a field it may guess at.
  if type(raw) ~= "table" or (raw.v ~= 1 and raw.v ~= 2 and raw.v ~= 3) then return false end
  if type(raw.generatedAt) ~= "number" then return false end
  if type(raw.runs) ~= "table" then return false end

  local db = GC.db
  if type(db) ~= "table" then return false end
  db.runsMeta = db.runsMeta or {}
  if raw.generatedAt <= (db.runsMeta.generatedAt or 0) then return false end

  local kept = {}
  for code, run in pairs(db.runs or {}) do
    if run.origin == "paste" then kept[code] = run end
  end
  if type(db.runNotices) ~= "table" then db.runNotices = {} end
  for _, rawRun in ipairs(raw.runs) do
    local run = copyRun(rawRun, "app")
    if run then
      -- Compared against what this code held BEFORE the replacement: `db.runs` is still the
      -- previous generation here, and a paste is never compared -- the site did not write it,
      -- so it has nothing to say about it having changed.
      local old = db.runs and db.runs[run.code] or nil
      if old and old.origin == "app" then
        local notice = noticeFor(old, run)
        if notice then db.runNotices[run.code] = notice end
      end
      pruneAlertProgress(db, run)
      kept[run.code] = run
    end
  end

  db.runs = kept
  -- A run the site deleted takes every per-run setting with it. Nothing else would ever clear
  -- them, and a code the site later reuses would come back carrying a cap, a split or a notice
  -- nobody chose for it. Named fields, not `{ db.runCaps, db.runsArchived, ... }`: whichever of
  -- these is nil (usually runCaps -- most runs never get one) would leave a hole in that array
  -- constructor, and ipairs stops dead at the first nil, silently skipping every store after it.
  for _, field in ipairs({ "runCaps", "runsArchived", "runSplits", "runNotices" }) do
    local store = db[field]
    if type(store) == "table" then
      for code in pairs(store) do
        if not kept[code] then store[code] = nil end
      end
    end
  end
  -- ...and a notice the band has already stopped showing goes with it. A notice is a claim about
  -- today (UI/BuyFrame.lua drops one a day old), so a run the site keeps sending would otherwise
  -- hold one that nobody will ever be shown again, in SavedVariables, for as long as it exists.
  for code, notice in pairs(db.runNotices) do
    local at = type(notice) == "table" and tonumber(notice.at) or nil
    if not at or (time() - at) >= 86400 then db.runNotices[code] = nil end
  end
  db.runsMeta = { generatedAt = raw.generatedAt }
  return true
end

local function archivedSet()
  local db = GC.db
  if type(db) ~= "table" then return nil end
  if type(db.runsArchived) ~= "table" then db.runsArchived = {} end
  return db.runsArchived
end

--- Whether this run has been put away. The flag lives beside the runs rather than on them,
--- because Adopt() replaces every "app" run wholesale on each sync and a flag stored on the run
--- itself would be handed back to the picker by the next one.
function GC.AppRuns.IsArchived(code)
  local set = archivedSet()
  return (set ~= nil and code ~= nil and set[code] == true) or false
end

--- Whether this run is an alert group's live hits rather than a saved list. The site owns it
--- entirely: it appears when the group has hits and goes when it does not, so there is nothing
--- here for the player to archive or remove.
function GC.AppRuns.IsAlert(code)
  local run = GC.AppRuns.Get(code)
  return (run ~= nil and run.k == "alert") or false
end

--- Whether this run belongs to somebody else and the player merely follows it. Same answer for
--- the same reason: Unfollow lives on goldcap.gg, and a local Remove would only last until the
--- next sync brought it back.
function GC.AppRuns.IsShared(code)
  local run = GC.AppRuns.Get(code)
  return (run ~= nil and type(run.by) == "string" and run.by ~= "") or false
end

--- Puts a run away, or takes it back out. Restoring CLEARS the entry rather than storing false,
--- so an unarchived run leaves nothing behind in SavedVariables to explain later.
function GC.AppRuns.SetArchived(code, archived)
  local set = archivedSet()
  if not set or type(code) ~= "string" or code == "" then return false end
  -- Neither an alert run nor a followed one may be put away: the site decides whether they are
  -- there at all, and a run that came back on the next sync with a stale flag on it would go
  -- straight into the Archived section unseen. Clearing a flag is always allowed, so one left
  -- behind by an older build has a way out.
  if archived and (GC.AppRuns.IsAlert(code) or GC.AppRuns.IsShared(code)) then return false end
  set[code] = archived and true or nil
  return true
end

-- Own app runs, then followed ones, then pastes, then alert groups; each group newest
-- `updatedAt` first. `opts.archived` asks for the other half instead -- the runs that have been
-- put away -- because the picker and the menu's archived section each want exactly one of the two.
function GC.AppRuns.List(opts)
  local wantArchived = type(opts) == "table" and opts.archived == true
  local db = GC.db
  if type(db) ~= "table" or type(db.runs) ~= "table" then return {} end
  local own, shared, pasteRuns, alerts = {}, {}, {}, {}
  for _, run in pairs(db.runs) do
    if GC.AppRuns.IsArchived(run.code) == wantArchived then
      if run.k == "alert" then
        alerts[#alerts + 1] = run
      elseif run.origin == "paste" then
        pasteRuns[#pasteRuns + 1] = run
      elseif type(run.by) == "string" and run.by ~= "" then
        shared[#shared + 1] = run
      else
        own[#own + 1] = run
      end
    end
  end
  local function newestFirst(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end
  table.sort(own, newestFirst)
  table.sort(shared, newestFirst)
  table.sort(pasteRuns, newestFirst)
  table.sort(alerts, newestFirst)
  local result = {}
  -- Own lists first, then the ones the player follows, then their own pastes, then the alert
  -- groups: the picker reads as "yours, then other people's, then what your alerts found", and
  -- a first visit (UI/BuyFrame.lua's ensureRun takes the first) never lands on somebody else's.
  for _, bucket in ipairs({ own, shared, pasteRuns, alerts }) do
    for _, run in ipairs(bucket) do result[#result + 1] = run end
  end
  return result
end

function GC.AppRuns.Get(code)
  local db = GC.db
  if type(db) ~= "table" or type(db.runs) ~= "table" then return nil end
  return db.runs[code]
end

-- djb2, folded into 32 bits with plain arithmetic (Lua 5.1 has no bitwise operators) --
-- not cryptographic, just a stable 8-hex-digit fingerprint so two different pastes with no
-- code of their own don't collide onto the same run slot.
local function hash8(str)
  local h = 5381
  for i = 1, #str do
    h = (h * 33 + str:byte(i)) % 4294967296
  end
  return ("%08x"):format(h)
end

local function decodeURIComponent(s)
  return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- Parses `GCR1;<code>;<uri-encoded name>;<itemId>=<qty>[=v][@usual][~vendorUnit],...` -- the
-- manual-paste twin of the companion's `GoldCap_AppRuns` global, for a player without the
-- companion running. The suffixes may come in any order and any of them may be absent. A
-- pasted run never carries per-line names (the string has none to carry): UI/ImportDialog.lua
-- and whatever draws the run fall back to the client's own item name for each line.
--
-- On success this also stores the run into `GC.db.runs` (origin "paste"), the same way a
-- successful GCS1 price import is applied immediately rather than just handed back parsed --
-- there is no second "now save it" step for a manual paste to skip.
function GC.AppRuns.ImportString(str)
  if type(str) ~= "string" then return nil, "bad_header" end
  str = str:gsub("%s+", "")
  local code, rawName, rest = str:match("^GCR1;([^;]*);([^;]*);(.*)$")
  if not code then return nil, "bad_header" end

  local parsed = {}
  for token in rest:gmatch("[^,]+") do
    local id, qty, suffix = token:match("^(%d+)=(%d+)(.*)$")
    if id then
      -- Suffixes in any order: `=v` marks a vendor stop, `@n` the site's usual unit price, `~n`
      -- the vendor's. Each recognised piece is struck out and whatever is left must be empty --
      -- a token with anything else in it is a typo, not a line, and is dropped exactly as an
      -- unparseable token always was.
      local leftover = suffix:gsub("=v", ""):gsub("@%d+", ""):gsub("~%d+", "")
      if leftover == "" then
        parsed[#parsed + 1] = {
          i = tonumber(id), q = tonumber(qty),
          v = suffix:find("=v", 1, true) ~= nil,
          u = tonumber(suffix:match("@(%d+)")),
          vu = tonumber(suffix:match("~(%d+)")),
        }
      end
    end
  end
  -- Same merge Adopt does, for the same reason (see mergeLines): a pasted string can name one
  -- item twice just as easily as the companion's file can.
  local lines = mergeLines(parsed)
  if #lines == 0 then return nil, "no_lines" end

  if code == "" then code = "paste-" .. hash8(rest) end
  local name = decodeURIComponent(rawName)
  if name == "" then name = nil end

  local run = { code = code, name = name, updatedAt = time(), lines = lines, origin = "paste" }

  local db = GC.db
  if type(db) == "table" then
    db.runs = db.runs or {}
    db.runs[run.code] = run
    -- A paste is the player asking for this run now; a flag left over from archiving an
    -- earlier copy would drop the fresh one straight into the Archived section unseen.
    if type(db.runsArchived) == "table" then db.runsArchived[run.code] = nil end
  end
  return run
end

-- Forgets a run. Any origin is accepted, but an "app" run is the companion's mirror of a list
-- on goldcap.gg and Adopt() brings it back on the next sync -- the caller decides whether to
-- offer that (UI/BuyFrame.lua offers removal for pasted runs only).
function GC.AppRuns.Remove(code)
  local db = GC.db
  if type(db) ~= "table" or type(db.runs) ~= "table" or type(code) ~= "string" then return false end
  if not db.runs[code] then return false end
  -- An alert run and a followed run are the site's: Unfollow and the alert group itself live on
  -- goldcap.gg, and removing one here would last exactly until the next sync.
  if GC.AppRuns.IsAlert(code) or GC.AppRuns.IsShared(code) then return false end
  db.runs[code] = nil
  -- Everything stored beside the run goes with it, for the same reason Adopt prunes: nothing
  -- else would. Named fields, not an array of the values -- see Adopt's pruning loop for why.
  for _, field in ipairs({ "runCaps", "runsArchived", "runSplits", "runNotices" }) do
    local store = db[field]
    if type(store) == "table" then store[code] = nil end
  end
  return true
end
