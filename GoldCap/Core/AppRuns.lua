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
  for _, rawRun in ipairs(raw.runs) do
    local run = copyRun(rawRun, "app")
    if run then kept[run.code] = run end
  end

  db.runs = kept
  -- A run the site deleted takes its per-run settings with it. Nothing else would ever clear
  -- them, and a code the site later reuses would come back carrying a cap nobody chose for it.
  local caps = db.runCaps
  if type(caps) == "table" then
    for code in pairs(caps) do
      if not kept[code] then caps[code] = nil end
    end
  end
  local archived = db.runsArchived
  if type(archived) == "table" then
    for code in pairs(archived) do
      if not kept[code] then archived[code] = nil end
    end
  end
  db.runsMeta = {
    plan = raw.plan == "pro" and "pro" or "free",
    freeLines = num(raw.freeLines) or 5,
    generatedAt = raw.generatedAt,
  }
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

--- Puts a run away, or takes it back out. Restoring CLEARS the entry rather than storing false,
--- so an unarchived run leaves nothing behind in SavedVariables to explain later.
function GC.AppRuns.SetArchived(code, archived)
  local set = archivedSet()
  if not set or type(code) ~= "string" or code == "" then return false end
  set[code] = archived and true or nil
  return true
end

-- App runs first, then paste runs, each group newest `updatedAt` first -- the board reads
-- top to bottom as "what the companion just gave you, then what you pasted yourself".
-- `opts.archived` asks for the other group instead -- the runs that have been put away --
-- because the picker and the menu's archived section each want exactly one of the two.
function GC.AppRuns.List(opts)
  local wantArchived = type(opts) == "table" and opts.archived == true
  local db = GC.db
  if type(db) ~= "table" or type(db.runs) ~= "table" then return {} end
  local appRuns, pasteRuns = {}, {}
  for _, run in pairs(db.runs) do
    if GC.AppRuns.IsArchived(run.code) == wantArchived then
      if run.origin == "paste" then
        pasteRuns[#pasteRuns + 1] = run
      else
        appRuns[#appRuns + 1] = run
      end
    end
  end
  local function newestFirst(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end
  table.sort(appRuns, newestFirst)
  table.sort(pasteRuns, newestFirst)
  local result = {}
  for _, run in ipairs(appRuns) do result[#result + 1] = run end
  for _, run in ipairs(pasteRuns) do result[#result + 1] = run end
  return result
end

function GC.AppRuns.Get(code)
  local db = GC.db
  if type(db) ~= "table" or type(db.runs) ~= "table" then return nil end
  return db.runs[code]
end

-- nil means unlimited (Pro); otherwise how many non-vendor lines of a run are unlocked --
-- see Core/BuyRun.lua's Refresh, which locks every line past this count.
function GC.AppRuns.FreeLines()
  local meta = GC.db and GC.db.runsMeta
  if type(meta) ~= "table" then return 5 end
  if meta.plan == "pro" then return nil end
  return meta.freeLines or 5
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
  db.runs[code] = nil
  -- Its cap and its archived flag go with it, for the same reason Adopt prunes them: nothing
  -- else would.
  if type(db.runCaps) == "table" then db.runCaps[code] = nil end
  if type(db.runsArchived) == "table" then db.runsArchived[code] = nil end
  return true
end
