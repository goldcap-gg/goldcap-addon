local _, GC = ...

-- What AUTO is doing on DEALS, in words: the two short lines under the toolbar's square buttons
-- and the block under the AUTO button's tooltip (UI/SniperFrame.lua gathers the state and paints).
-- Pure: it reads plain tables and answers text, and keeps one rolling count of what AUTO did in
-- the last five minutes, fed where each thing happens (Note).
--
-- The state (every field optional; seconds are plain numbers, already measured by the caller):
--   paused  AUTO is off or held: the chip says why, so no new line (Lines answers { dim = true })
--   pass    the commodity browse pass: { page, pages, items, seconds, lapPages, lastAgo }
--           page: the page being read now (nil between passes); lapPages: the pages of the last
--           complete lap of the same kind; items, seconds: the last complete lap's; lastAgo: how
--           long ago it ended; finds: its hits
--   items   the Items board's realm poll: { round, batch, batches, targets, nextIn }
--   caps    the caps' poll: { count, batch, batches, nextIn }
--   full    the full scan (WoW: Forever): { running, dueIn }
--   gear    the gear loop (WoW: Forever's Items board): { armor, page, seconds, last }
--   queue   checks waiting: { depth, oldest }
--   hot     items in the after-deal hot set
--   moved   the last browse pass's prices moved on DEALS (WoW: Forever)
--   counts  { finds, checked, deals } over the last five minutes (Counts)
--   perMinute  the addon's queries in the last minute (GC.Util.SendsPerMinute)
local AR = {}
GC.AutoReadout = AR

AR.WINDOW_SECONDS = 300
local SEP = " · "

local events = {} -- { at, kind }, oldest first

local function clock(now) return now or (GetTime or time)() end

local function prune(now)
  local keep = 1
  while events[keep] and now - events[keep].at >= AR.WINDOW_SECONDS do keep = keep + 1 end
  if keep > 1 then
    local kept = {}
    for i = keep, #events do kept[#kept + 1] = events[i] end
    events = kept
  end
end

-- A find went into the drill queue ("finds"), a check of one was answered ("checked"), a deal
-- rang the bell ("deals").
function AR.Note(kind, now)
  now = clock(now)
  prune(now)
  events[#events + 1] = { at = now, kind = kind }
end

function AR.Counts(now)
  prune(clock(now))
  local c = { finds = 0, checked = 0, deals = 0 }
  for _, e in ipairs(events) do
    if c[e.kind] then c[e.kind] = c[e.kind] + 1 end
  end
  return c
end

function AR._Reset() events = {} end

local function n(v) return GC.Util.Grouped(v or 0) end
local function secs(v) return n(math.floor((v or 0) + 0.5)) end
local function join(parts) return table.concat(parts, SEP) end

-- Each rung a list of parts, the longest first; a rung is the parts joined, and one that says no
-- less than the rung before it is left out.
local function rungs(list)
  local out = {}
  for _, parts in ipairs(list) do
    local text = join(parts)
    if text ~= out[#out] then out[#out + 1] = text end
  end
  return out
end

-- Whether two states hold the same figures, so the caller writes nothing when nothing moved.
function AR.Same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not AR.Same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

-- The first rung `measure` says is no wider than `width`, or nil when none is: never cut.
function AR.Fit(list, width, measure)
  for _, text in ipairs(list or {}) do
    if measure(text) <= width then return text end
  end
  return nil
end

local function gearHead(g)
  return (g.armor and GC.L["Armor: page %s"] or GC.L["Weapons: page %s"]):format(n(math.max(g.page or 0, 1)))
end

local function itemsRungs(it)
  local targets = GC.L["%s targets"]:format(n(it.targets))
  if it.nextIn then
    return rungs({ { GC.L["Items: next round in %s s"]:format(secs(it.nextIn)), targets },
      { GC.L["Items: next round in %s s"]:format(secs(it.nextIn)) } })
  end
  local head = GC.L["Items: round %s"]:format(n(it.round))
  local batch = GC.L["batch %s of %s"]:format(n(it.batch), n(it.batches))
  return rungs({ { head, batch, targets }, { head, batch }, { head } })
end

local function passRungs(p, full)
  local items = p.items and GC.L["%s items"]:format(n(p.items))
  local lap = p.seconds and GC.L["lap %s s"]:format(secs(p.seconds))
  local due = full and full.dueIn and (full.dueIn > 0 and GC.L["full scan in %s min"]:format(n(math.ceil(full.dueIn / 60)))
    or GC.L["full scan ready"])
  local long, short
  if p.page then
    short = GC.L["Pass: page %s"]:format(n(p.page))
    long = (p.lapPages and p.page <= p.lapPages) and GC.L["Pass: page %s of %s"]:format(n(p.page), n(p.lapPages)) or short
  elseif p.lastAgo then
    short = GC.L["Last lap %s s ago"]:format(secs(p.lastAgo))
    long = short
  else
    return nil
  end
  local function with(head, ...)
    local parts = { head }
    for _, part in ipairs({ ... }) do parts[#parts + 1] = part end
    return parts
  end
  -- The least important goes first: the full scan's countdown (the SCAN button carries it too),
  -- then the "of N", then the lap time, then the items.
  local list = {}
  if due then list[#list + 1] = with(long, items, lap, due) end
  list[#list + 1] = with(long, items, lap)
  list[#list + 1] = with(short, items, lap)
  list[#list + 1] = with(short, items)
  list[#list + 1] = { short }
  return rungs(list)
end

-- The first line's rungs: what runs now.
local function nowRungs(s)
  if s.full and s.full.running then return { GC.L["Full scan running"] } end
  local g = s.gear
  if g then
    if g.seconds then
      local head = gearHead(g)
      return rungs({ { head, GC.L["round %s s"]:format(secs(g.seconds)) }, { head } })
    end
    if g.last then return { GC.L["Gear loop: %s"]:format(GC.L["last round %s s"]:format(secs(g.last))) } end
    return nil
  end
  if s.items and (s.items.targets or 0) > 0 then return itemsRungs(s.items) end
  if s.pass then return passRungs(s.pass, s.full) end
  return nil
end

local function recentParts(s)
  local c = s.counts or {}
  return GC.L["%s finds"]:format(n(c.finds)), GC.L["%s checked"]:format(n(c.checked)),
    GC.L["%s deals"]:format(n(c.deals))
end

-- The line's two rungs lists: { now = {...} or nil, recent = {...}, dim = false }, or { dim = true }
-- while AUTO is paused (the caller keeps the last figures, dimmed).
function AR.Lines(s)
  s = s or {}
  if s.paused then return { dim = true } end
  local finds, checked, deals = recentParts(s)
  local req = GC.L["%s req/min"]:format(n(s.perMinute))
  local recent = {}
  for _, parts in ipairs({ { finds, checked, deals, req }, { finds, checked, deals }, { finds, deals }, { deals } }) do
    recent[#recent + 1] = GC.L["5 min: %s"]:format(join(parts))
  end
  return { dim = false, now = nowRungs(s), recent = recent }
end

-- The tooltip's block, one line each.
function AR.Tooltip(s)
  s = s or {}
  local out = {}
  local function add(text, value) out[#out + 1] = text:format(value) end
  local now = not s.paused and nowRungs(s)
  add(GC.L["Now: %s"], now and now[1] or (s.paused and GC.L["paused"] or GC.L["waiting"]))
  local p = s.pass
  if p and p.seconds then
    add(GC.L["Last lap: %s"], join({ GC.L["%s s"]:format(secs(p.seconds)), GC.L["%s items"]:format(n(p.items)),
      GC.L["%s finds"]:format(n(p.finds)) }))
  elseif p then
    add(GC.L["Last lap: %s"], GC.L["none yet"])
  end
  if s.queue then
    local q = s.queue
    add(GC.L["Checks waiting: %s"], (q.depth or 0) > 0 and q.oldest
      and join({ n(q.depth), GC.L["oldest %s s"]:format(secs(q.oldest)) }) or n(q.depth))
  end
  local it = s.items
  if it and (it.targets or 0) > 0 then
    add(GC.L["Items poll: %s"], join({ GC.L["%s targets"]:format(n(it.targets)), it.nextIn
      and GC.L["next round in %s s"]:format(secs(it.nextIn))
      or join({ GC.L["round %s"]:format(n(it.round)), GC.L["batch %s of %s"]:format(n(it.batch), n(it.batches)) }) }))
  end
  local c = s.caps
  if c and (c.count or 0) > 0 then
    add(GC.L["Your prices: %s"], join({ n(c.count), c.nextIn and GC.L["next round in %s s"]:format(secs(c.nextIn))
      or GC.L["batch %s of %s"]:format(n(c.batch), n(c.batches)) }))
  end
  if s.hot then add(GC.L["Hot items: %s"], n(s.hot)) end
  add(GC.L["5 min: %s"], join({ recentParts(s) }))
  add(GC.L["Requests: %s per minute"], n(s.perMinute))
  local f = s.full
  if f then
    add(GC.L["Full scan: %s"], f.running and GC.L["running"]
      or (f.dueIn and f.dueIn > 0 and GC.L["in %s min"]:format(n(math.ceil(f.dueIn / 60))))
      or GC.L["ready"])
  end
  if s.moved then add(GC.L["Last pass: %s new prices on DEALS"], n(s.moved)) end
  local g = s.gear
  if g then
    add(GC.L["Gear loop: %s"], g.seconds and join({ gearHead(g), GC.L["round %s s"]:format(secs(g.seconds)) })
      or (g.last and GC.L["last round %s s"]:format(secs(g.last))) or GC.L["waiting"])
  end
  return out
end
