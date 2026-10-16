local _, GC = ...

-- The welcome window's decisions (UI/WelcomeFrame.lua draws them): what state the player's prices
-- are in, and whether to open the window on this auction house visit. Pure: everything it reads
-- comes in as arguments, so spec/welcome_spec.lua drives every case without a client.
--
-- Why a window at all: on retail, prices without the Companion are the snapshot GoldCap shipped
-- with, and Deals cannot arm on it at all (the snapshot carries no sale facts, Core/Trigger.lua
-- needs a stressUnit), so a player without the Companion watches an empty board and concludes
-- there is nothing to buy. On WoW: Forever the addon works from the player's own scans, and the
-- Companion adds every other player's.
--
-- When: the first auction house visit after installing (the whole welcome), and after that only
-- while the prices are in a bad state, at most every few days, until the player says stop. Never
-- at login: the auction house is where the empty board is, so that is where the reason makes sense.
GC.Welcome = GC.Welcome or {}
local Welcome = GC.Welcome

Welcome.C = {
  -- The Companion writes every 30 minutes and the addon reads it at login or /reload, so a long
  -- session ages the prices on its own. Past a day, the Companion is not running.
  STALE_SECONDS = 24 * 3600,
  -- How soon the window comes back while the prices stay bad: Deals finds nothing, or finds it
  -- on prices a day old or more.
  REMIND_BAD_SECONDS = 3 * 86400,
  -- And while they work but could be better: a fresh paste, or WoW: Forever on own scans alone.
  REMIND_WARN_SECONDS = 7 * 86400,
}
local C = Welcome.C

local function age(now, ts)
  if type(ts) ~= "number" or ts <= 0 or type(now) ~= "number" then return nil end
  return math.max(0, now - ts)
end

--- The state of the player's prices, from what the client holds. `input`:
--   now          epoch seconds
--   forever      true on WoW: Forever
--   retail: origin ("none" | "manual" | "app", GC.Data.OriginState), importedTs, bundledTs,
--           appError ({ reason }, GC.Data.AppDataError)
--   forever: crowdTs (the Companion's payload for this auction house), companion (true when the
--            Companion has written GoldCap_AppData on this computer)
-- Returns { kind, tone = "bad" | "warn" | "good", age = seconds | nil, cta = "install" | "run" |
-- "update" | nil, reason = parser code | nil }. `cta` is what the window asks of the player:
-- install the Companion, start it again, or update both.
function Welcome.Prices(input)
  local now = input.now
  if input.forever then
    local crowd = age(now, input.crowdTs)
    if crowd and crowd < C.STALE_SECONDS then
      return { kind = "crowd", tone = "good", age = crowd }
    elseif crowd then
      return { kind = "crowd_stale", tone = "warn", age = crowd, cta = "run" }
    elseif input.companion then
      return { kind = "crowd_missing", tone = "warn", cta = "run" }
    end
    return { kind = "own", tone = "warn", cta = "install" }
  end

  if input.appError then
    return { kind = "error", tone = "bad", cta = "update", reason = input.appError.reason }
  end
  local imported = age(now, input.importedTs)
  if input.origin == "app" and imported then
    if imported < C.STALE_SECONDS then return { kind = "app", tone = "good", age = imported } end
    return { kind = "app_stale", tone = "bad", age = imported, cta = "run" }
  end
  if input.origin == "manual" and imported then
    if imported < C.STALE_SECONDS then
      return { kind = "manual", tone = "warn", age = imported, cta = "install" }
    end
    return { kind = "manual_stale", tone = "bad", age = imported, cta = "install" }
  end
  return { kind = "bundled", tone = "bad", age = age(now, input.bundledTs), cta = "install" }
end

--- Called once at ADDON_LOADED with the save and whether it was created just now: a save that did
-- not exist is a new player, who gets the whole welcome; everyone else only the prices part, and
-- only when their prices need it.
function Welcome.OnLoad(db, fresh)
  if type(db) ~= "table" then return end
  if type(db.welcome) ~= "table" then db.welcome = { firstRun = fresh and true or nil } end
end

--- What to open on this auction house visit, if anything: "welcome" (the whole window, a new
-- player's first visit), "prices" (the prices part alone) or nil. `w` is GoldCapDB.welcome.
function Welcome.Decide(w, status, now)
  if type(w) ~= "table" or type(status) ~= "table" then return nil end
  if not w.seen then
    if w.firstRun then return "welcome" end
    if status.tone ~= "good" then return "prices" end
    return nil
  end
  if w.quiet or status.tone == "good" then return nil end
  if (now or 0) < (w.nextAt or 0) then return nil end
  return "prices"
end

local function interval(status)
  return status and status.tone == "bad" and C.REMIND_BAD_SECONDS or C.REMIND_WARN_SECONDS
end

--- The window opened by itself: it has been seen, and comes back no sooner than the state's own
-- interval.
function Welcome.MarkShown(w, status, now)
  if type(w) ~= "table" then return end
  w.seen, w.firstRun = true, nil
  w.nextAt = (now or 0) + interval(status)
end

--- The player opened it (/gc companion, the Deals window's price line): seen. A reminder clock
-- already running is left alone; with none yet, one starts now, so a player who opened it before
-- ever visiting the auction house is not shown it again on arrival.
function Welcome.MarkOpened(w, status, now)
  if type(w) ~= "table" then return end
  w.seen, w.firstRun = true, nil
  if w.nextAt == nil then w.nextAt = (now or 0) + interval(status) end
end

--- "Don't remind me": the window never opens by itself again. /gc companion still opens it.
function Welcome.Quiet(w)
  if type(w) ~= "table" then return end
  w.quiet = true
end
