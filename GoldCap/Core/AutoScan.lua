local _, GC = ...

-- Sniper v3 §3: a pure state machine for the Auto-scan loop. No WoW API calls
-- live here -- SniperFrame.lua wires real events/timers to GC.AutoScan.New's
-- injected `actions` and feeds this module the exact event strings below via
-- :Input(event, now). Every timer is a `deadline` field compared against the
-- `now` passed to :Tick(now); nothing here reads a wall clock itself.

GC.AutoScan = {}

local DEFAULT_BREATHER = 2
local DEFAULT_SETTLE = 1

-- Pause causes are a SET (dialog/search/mail/ah/tab can overlap -- e.g. a
-- buy dialog opened while the player's own search is also live) rather than
-- a single flag: the machine only resumes once every cause has cleared.
function GC.AutoScan.New(timers, actions)
  timers = timers or {}
  local breather = timers.breather or DEFAULT_BREATHER
  local settle = timers.settle or DEFAULT_SETTLE

  local obj = {}
  local state = "OFF" -- OFF | IDLE | SCANNING | WAITING | PAUSED
  local reasons = {}
  local deadline = nil

  local function hasReasons()
    return next(reasons) ~= nil
  end

  -- Entering any pause while SCANNING aborts the in-flight pagination
  -- exactly once (resume always issues a fresh browse query -- the aborted
  -- pass's browse state must be assumed clobbered, see spec §3). Pausing
  -- during IDLE/WAITING has nothing to abort.
  local function addPause(reason)
    if state == "OFF" then return end
    if reasons[reason] then return end
    reasons[reason] = true
    if state == "SCANNING" then
      actions.abortScan()
    end
    state = "PAUSED"
    deadline = nil
  end

  -- The set emptying starts a `settle` countdown (WAITING); Tick fires
  -- startScan once it elapses with no reasons re-added in the meantime.
  local function removePause(reason, now)
    if state == "OFF" then return end
    if not reasons[reason] then return end
    reasons[reason] = nil
    if not hasReasons() then
      state = "WAITING"
      deadline = now + settle
    end
  end

  -- scanFinished only means anything mid-scan; a stray/duplicate event is a
  -- no-op (also covers state == "OFF").
  local function onScanFinished(now)
    if state ~= "SCANNING" then return end
    state = "WAITING"
    deadline = now + breather
  end

  local function toggleOn()
    if state ~= "OFF" then return end
    reasons = {}
    deadline = nil
    state = "IDLE"
  end

  -- From any state: abort if a scan is in flight, then go OFF. OFF ignores
  -- every other input until toggleOn re-arms it.
  local function toggleOff()
    if state == "OFF" then return end
    if state == "SCANNING" then
      actions.abortScan()
    end
    state = "OFF"
    reasons = {}
    deadline = nil
  end

  local handlers = {
    toggleOn = toggleOn,
    toggleOff = toggleOff,
    -- ahClosed/tabHidden behave as pause reasons "ah"/"tab": Auto stays
    -- armed while the AH is closed or the Sniper tab isn't shown, and
    -- resumes (after settle) once the AH reopens / the tab is shown again.
    ahOpened = function(now) removePause("ah", now) end,
    ahClosed = function() addPause("ah") end,
    tabShown = function(now) removePause("tab", now) end,
    tabHidden = function() addPause("tab") end,
    scanFinished = onScanFinished,
    ["pause:dialog"] = function() addPause("dialog") end,
    ["resume:dialog"] = function(now) removePause("dialog", now) end,
    ["pause:search"] = function() addPause("search") end,
    ["resume:search"] = function(now) removePause("search", now) end,
    ["pause:mail"] = function() addPause("mail") end,
    ["resume:mail"] = function(now) removePause("mail", now) end,
    ["pause:sell"] = function() addPause("sell") end,
    ["resume:sell"] = function(now) removePause("sell", now) end,
    -- The Items board is on screen: its keys batches and the pass share one browse buffer,
    -- and a pass paging under the poll left both boards half-answered (see UI/SniperFrame.lua's
    -- _SetBoard). The pass waits, exactly as it does for the Sell tab.
    ["pause:items"] = function() addPause("items") end,
    ["resume:items"] = function(now) removePause("items", now) end,
  }

  function obj:Input(event, now)
    local handler = handlers[event]
    if handler then handler(now) end
  end

  -- Drives the breather/settle timers; call from OnUpdate (~4Hz). IDLE
  -- starts a scan on the very next Tick with no reasons pending; WAITING
  -- starts one once its deadline has passed and reasons are still empty.
  --
  -- The state only advances on a scan that actually started. It used to advance
  -- regardless, and the caller's startScan withholds the send whenever the player
  -- is busy on Blizzard's own auction house panes -- so the machine sat in
  -- SCANNING with nothing in flight and no event that could ever move it on. The
  -- button said "AUTO · SCANNING" for as long as the player cared to watch it,
  -- and no scan ran. A `false` answer keeps the machine in WAITING with a fresh
  -- settle deadline, so the very next opening starts one for real. Anything else
  -- (including an action that returns nothing, which is every older caller and
  -- every spec fake) is taken at its word that a scan is running.
  local function beginScan(now)
    if actions.startScan() == false then
      state = "WAITING"
      deadline = now + settle
      return
    end
    state = "SCANNING"
    deadline = nil
  end

  function obj:Tick(now)
    if state == "IDLE" then
      if not hasReasons() then
        beginScan(now)
      end
    elseif state == "WAITING" then
      if deadline and now >= deadline and not hasReasons() then
        beginScan(now)
      end
    end
  end

  function obj:State()
    return state
  end

  function obj:PauseReasons()
    local copy = {}
    for k in pairs(reasons) do copy[k] = true end
    return copy
  end

  return obj
end
