local _, GC = ...

-- WoW: Forever's Road to 40 (plan 3e, growth spec D8): the gold a character has toward its
-- level-40 riding -- its money plus its bags at what they fetch (each stack at the better of a
-- vendor and the auction house after its cut, Core/ForeverValue.lua) -- against the cost the
-- player set, and the level it gets there at the pace it has been playing.
--
-- The riding cost is the player's own setting (GoldCapDB.forever.mountCost, /gc mount): Blizzard
-- has not published it, and GoldCap does not guess it (growth spec, honesty guards).
--
-- Pace: each character keeps its own played-time clock and a few samples of its gold and level
-- progress (GoldCapDB.forever.road[<character GUID>]); the rate is measured over the last
-- WINDOW_SECONDS of play. Only time logged in counts. Nothing here leaves this computer.
GC.ForeverRoad = GC.ForeverRoad or {}

local C = {
  TARGET_LEVEL = 40,          -- the beta's riding records sit at level 40 (research F4); the lines say 40
  SAMPLE_SECONDS = 300,       -- one pace sample per five minutes played
  MAX_SAMPLES = 48,           -- four hours of them
  WINDOW_SECONDS = 3 * 3600,  -- the pace is measured over the last three hours played
  MIN_RATE_SECONDS = 20 * 60, -- and not before twenty minutes of it
  GAP_SECONDS = 180,          -- a longer silence between two ticks is time away, never play
  TICK_SECONDS = 60,          -- the clock's own ticker, so a quiet stretch of play still counts
}
GC.ForeverRoad.C = C

local function prefs()
  return GC.ForeverScan and GC.ForeverScan.Prefs and GC.ForeverScan.Prefs() or nil
end

-- "12g 50s", "12g50s", "3s 20c", "90" (a bare number is gold, "0.5" half of one). nil for anything
-- else, and for zero: a cost of nothing is not a cost. The parser itself is GC.Util.ParseMoney,
-- shared with every other price box: this file is WoW: Forever's own and shared code must not
-- reach into it.
function GC.ForeverRoad.ParseMoney(text)
  return GC.Util.ParseMoney(text)
end

-- Money for a line the player sends in chat: letters, no coin icons (chat strips texture escapes).
-- `g` goes through GC.Util.IntText, not %d: WoW's own string.format raises "integer overflow
-- attempting to store N" past +-2^31 copper (about 214,748g), same as Core/ForeverFold.lua's
-- Encode. `s`/`c` stay on %d -- both are bounded 0-99 by the mod above and can never reach it.
function GC.ForeverRoad.Plain(copper)
  copper = math.max(0, math.floor(tonumber(copper) or 0))
  local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  if g > 0 then
    return s > 0 and (GC.Util.IntText(g) .. "g " .. ("%ds"):format(s)) or (GC.Util.IntText(g) .. "g")
  end
  if s > 0 then return c > 0 and ("%ds %dc"):format(s, c) or ("%ds"):format(s) end
  return ("%dc"):format(c)
end

-- One reading of a character's clock: `now` epoch seconds, `money` copper, `progress` its level
-- plus the share of the level done (20.5 = halfway through 20).
function GC.ForeverRoad.Tick(c, now, money, progress)
  if type(c.last) == "number" and now >= c.last and now - c.last <= C.GAP_SECONDS then
    c.played = (c.played or 0) + (now - c.last)
  end
  c.played = c.played or 0
  c.last = now
  c.samples = type(c.samples) == "table" and c.samples or {}
  local lastSample = c.samples[#c.samples]
  local lastPlayed = lastSample and tonumber(lastSample:match("^(%d+)")) or nil
  if not lastPlayed or c.played - lastPlayed >= C.SAMPLE_SECONDS then
    c.samples[#c.samples + 1] = ("%d:%d:%.3f"):format(c.played, money, progress)
    while #c.samples > C.MAX_SAMPLES do table.remove(c.samples, 1) end
  end
  c.money, c.progress = money, progress
end

-- The session's last reading (logout): the next session's first tick counts nothing.
function GC.ForeverRoad.End(c, now, money, progress)
  GC.ForeverRoad.Tick(c, now, money, progress)
  c.last = nil
end

-- Copper and levels per hour played, from the oldest sample inside the window to the last reading.
-- nil before MIN_RATE_SECONDS of play.
function GC.ForeverRoad.Rate(c)
  if type(c) ~= "table" or type(c.samples) ~= "table" then return nil end
  if type(c.money) ~= "number" or type(c.progress) ~= "number" then return nil end
  local played = c.played or 0
  local from
  for _, sample in ipairs(c.samples) do
    local p, m, l = sample:match("^(%d+):(%-?%d+):([%d%.]+)$")
    p = tonumber(p)
    if p and played - p <= C.WINDOW_SECONDS then
      from = { p = p, m = tonumber(m), l = tonumber(l) }
      break
    end
  end
  if not from then return nil end
  local span = played - from.p
  if span < C.MIN_RATE_SECONDS then return nil end
  return (c.money - from.m) * 3600 / span, (c.progress - from.l) * 3600 / span
end

function GC.ForeverRoad.Forecast(s)
  local have = (s.money or 0) + (s.bags or 0)
  if type(s.cost) ~= "number" or s.cost <= 0 then return { kind = "nocost" } end
  if have >= s.cost then return { kind = "ready" } end
  if (s.level or 0) >= C.TARGET_LEVEL then return { kind = "past" } end
  if type(s.moneyRate) ~= "number" or type(s.levelRate) ~= "number" then return { kind = "norate" } end
  if s.moneyRate <= 0 then return { kind = "flat" } end
  -- A stalled or negative level rate (no XP progress lately) is not a dead end: `at` below then
  -- comes out at or under `progress`, so the "level" branch's own math.max already answers with
  -- the character's CURRENT level, exactly the honest thing to say. Only the character actually
  -- being at the level cap (checked above, before the rate is even read) stays "past".
  local need = s.cost - have
  local at = s.progress + s.levelRate * (need / s.moneyRate)
  if at <= C.TARGET_LEVEL then return { kind = "level", level = math.max(s.level, math.floor(at)) } end
  local hoursToTarget = (C.TARGET_LEVEL - s.progress) / s.levelRate
  return { kind = "short", short = need - math.floor(s.moneyRate * hoursToTarget) }
end

function GC.ForeverRoad.Lines(s)
  local coin, lines = GC.Util.CoinText, {}
  local have = (s.money or 0) + (s.bags or 0)
  local f = GC.ForeverRoad.Forecast(s)
  if f.kind == "nocost" then
    lines[1] = GC.L["Road to 40: you have %s (gold %s, bags %s)."]:format(coin(have), coin(s.money), coin(s.bags))
    lines[2] = GC.L["Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect."]
  else
    lines[1] = GC.L["Road to 40: %s of %s (gold %s, bags %s)."]:format(coin(have), coin(s.cost), coin(s.money),
      coin(s.bags))
    if f.kind == "ready" then
      lines[2] = GC.L["You can pay for it now."]
    elseif f.kind == "level" then
      lines[2] = GC.L["At your pace you reach it at level %d."]:format(f.level)
    elseif f.kind == "short" then
      lines[2] = GC.L["At your pace you will be %s short at level 40."]:format(coin(f.short))
    elseif f.kind == "norate" then
      lines[2] = GC.L["Play a little longer for an estimate of your pace."]
    elseif f.kind == "flat" then
      lines[2] = GC.L["Your gold has not grown lately, so there is no pace to estimate."]
    elseif f.kind == "past" then
      lines[2] = GC.L["Level 40 reached: %s to go."]:format(coin(s.cost - have))
    end
  end
  if (s.gainItems or 0) > 0 and (s.gain or 0) > 0 then
    lines[#lines + 1] = GC.L["Items in your bags that fetch more on the auction house than at a vendor: %d (%s more)."]
      :format(s.gainItems, coin(s.gain))
  end
  return lines
end

-- The line `/gc mount share` puts in the chat box: plain money, the level when there is one.
function GC.ForeverRoad.ShareText(s)
  if not s or type(s.cost) ~= "number" or s.cost <= 0 then return nil end
  local have = (s.money or 0) + (s.bags or 0)
  local pct = math.min(100, math.floor(have * 100 / s.cost))
  local text = GC.L["Road to 40 with GoldCap: %s of %s for my mount (%d%%)."]:format(
    GC.ForeverRoad.Plain(have), GC.ForeverRoad.Plain(s.cost), pct)
  local f = GC.ForeverRoad.Forecast(s)
  if f.kind == "level" then text = text .. " " .. GC.L["At your pace you reach it at level %d."]:format(f.level) end
  return text
end

-- The client. Every read is guarded: a missing API reads as nothing there, never an error.

local function readProgress()
  local okL, level = pcall(_G.UnitLevel, "player")
  level = okL and tonumber(level) or 1
  local okX, xp = pcall(_G.UnitXP, "player")
  local okM, max = pcall(_G.UnitXPMax, "player")
  xp, max = okX and tonumber(xp) or 0, okM and tonumber(max) or 0
  return level, level + ((max > 0) and math.min(1, xp / max) or 0)
end

local function currentChar(p)
  local ok, guid = pcall(_G.UnitGUID, "player")
  if not ok or type(guid) ~= "string" then return nil end
  p.road = type(p.road) == "table" and p.road or {}
  local c = p.road[guid]
  if type(c) ~= "table" then
    c = { played = 0, samples = {} }
    p.road[guid] = c
  end
  return c
end

local function money()
  local ok, m = pcall(GetMoney)
  return ok and tonumber(m) or 0
end

function GC.ForeverRoad.Snapshot()
  local p = prefs()
  if not p then return nil end
  local c = currentChar(p)
  local level, progress = readProgress()
  local bags = {}
  if GC.ForeverValue and type(GC.ForeverValue.RealBagTotals) == "function" then
    local ok, t = pcall(GC.ForeverValue.RealBagTotals)
    if ok and type(t) == "table" then bags = t end
  end
  local moneyRate, levelRate
  if c then moneyRate, levelRate = GC.ForeverRoad.Rate(c) end
  return { money = money(), bags = bags.best or 0, gain = bags.gain or 0, gainItems = bags.gainItems or 0,
    cost = (type(p.mountCost) == "number" and p.mountCost > 0) and p.mountCost or nil,
    level = level, progress = progress, moneyRate = moneyRate, levelRate = levelRate }
end

-- PLAYER_MONEY, PLAYER_XP_UPDATE, PLAYER_LEVEL_UP and the ticker. The ticker hands its callback
-- the ticker itself, so `now` is used only when it is a number.
function GC.ForeverRoad.OnTick(now)
  local p = prefs()
  if not p then return end
  local c = currentChar(p)
  if not c then return end
  local _, progress = readProgress()
  GC.ForeverRoad.Tick(c, type(now) == "number" and now or time(), money(), progress)
end

function GC.ForeverRoad.OnMoney()
  if not prefs() then return end
  GC.ForeverRoad.OnTick()
  if GC.Sold and GC.Sold.RefreshIfShown then GC.Sold.RefreshIfShown() end
end

function GC.ForeverRoad.OnEnteringWorld()
  if not prefs() then return end
  local timer = _G.C_Timer
  if GC.ForeverRoad._ticker == nil and type(timer) == "table" and type(timer.NewTicker) == "function" then
    GC.ForeverRoad._ticker = timer.NewTicker(C.TICK_SECONDS, GC.ForeverRoad.OnTick)
  end
  GC.ForeverRoad.OnTick()
end

function GC.ForeverRoad.OnLogout()
  local p = prefs()
  if not p then return end
  local c = currentChar(p)
  if not c then return end
  local _, progress = readProgress()
  GC.ForeverRoad.End(c, time(), money(), progress)
end

-- /gc mount [<amount> | clear | share]
function GC.ForeverRoad.Slash(rest)
  local p = prefs()
  if not p then return end
  rest = type(rest) == "string" and rest or ""
  local word = rest:lower()
  if word == "clear" then
    p.mountCost = nil
    GC.Print(GC.L["Mount cost cleared."])
    if GC.Sold and GC.Sold.RefreshIfShown then GC.Sold.RefreshIfShown() end
    return
  end
  if word == "share" then
    local text = GC.ForeverRoad.ShareText(GC.ForeverRoad.Snapshot())
    if not text then
      GC.Print(GC.L["Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect."])
    elseif type(_G.ChatFrame_OpenChat) == "function" then
      _G.ChatFrame_OpenChat(text)
    else
      GC.Print(text)
    end
    return
  end
  if word ~= "" then
    local copper = GC.ForeverRoad.ParseMoney(rest)
    if not copper then
      GC.Print(GC.L["Could not read that amount. Type it like 12g 50s."])
      return
    end
    p.mountCost = copper
    GC.Print(GC.L["Mount cost set to %s."]:format(GC.Util.CoinText(copper)))
  end
  for _, line in ipairs(GC.ForeverRoad.Lines(GC.ForeverRoad.Snapshot())) do GC.Print(line) end
  if GC.Sold and GC.Sold.RefreshIfShown then GC.Sold.RefreshIfShown() end
end
