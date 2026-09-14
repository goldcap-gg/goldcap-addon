local _, GC = ...

GC.Util = {}

function GC.Util.ApplyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      GC.Util.ApplyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function GC.Util.FormatAge(seconds)
  if seconds < 3600 then return "<1h" end
  if seconds < 48 * 3600 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

-- Compact gold display: whole gold past 100g, gold+silver below it, a coin-icon string
-- under a gold. Moved here (Sniper fast loop, phase 1) from UI/SniperFrame.lua's own
-- formatColumnAmount so Core/BoardRows.lua can format a verdict label without a WoW frame --
-- GetCoinTextureString is still a WoW global, so a caller without the client (this addon's
-- own spec suite) stubs it, exactly as every UI/SniperFrame.lua spec already does.
local GOLD_COMPACT_THRESHOLD = 100 * 10000 -- 100g in copper
function GC.Util.FormatMoney(copper)
  if copper < 0 then return "-" .. GC.Util.FormatMoney(-copper) end
  if copper >= GOLD_COMPACT_THRESHOLD then
    return ("%dg"):format(math.floor(copper / 10000))
  end
  if copper >= 10000 then
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if silver == 0 then return ("%dg"):format(gold) end
    return ("%dg%02ds"):format(gold, silver)
  end
  return GetCoinTextureString(copper)
end

-- Whole-gold-or-whole-silver: a context with room for ONE unit, never two, and no coin icon
-- (a plain string, for a FontString cell rather than a coin-texture readout). Sniper's SAFE
-- board label is the reason this exists -- FormatMoney's "61g35s" is two units wide, and the
-- 72px verdict cell it renders into clips it. Floors rather than rounds, same rule as
-- FormatAge/FormatElapsed above: a figure that rounds up promises gold the trade didn't clear.
function GC.Util.FormatGoldFloor(copper)
  if copper < 0 then return "-" .. GC.Util.FormatGoldFloor(-copper) end
  if copper >= 10000 then
    return ("%dg"):format(math.floor(copper / 10000))
  end
  return ("%ds"):format(math.floor(copper / 100))
end

local function finitePositive(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge and value > 0
end

-- How long the shelf lasts at the rate the market is clearing it, for the tooltip's depth
-- line. Floors to whole days the way FormatAge does, so a number the player reads never
-- rounds up into a promise the market has not made. Past 99 days the figure stops carrying
-- information -- "400d" and "99d+" say the same thing to a seller, and the short one does
-- not stretch the tooltip. nil means the question has no answer, either because nothing is
-- listed or because there are no sales to divide by; the caller then prints the stock alone
-- rather than inventing a rate.
function GC.Util.FormatSupplyDays(qty, soldPerDay)
  if not finitePositive(qty) or not finitePositive(soldPerDay) then return nil end
  local days = qty / soldPerDay
  if days < 1 then return "<1d" end
  local whole = math.floor(days)
  if whole > 99 then return "99d+" end
  return whole .. "d"
end

-- How long ago, for a figure the player is reading while deciding. FormatAge above answers
-- a coarser question ("is my whole snapshot stale") and collapses everything under an hour
-- to "<1h" -- which is exactly the resolution that matters on a live check. The Sniper's
-- check panel printed a raw "3384s" instead; this is what it should have been saying.
--
-- Floors at every step: a freshness figure that rounds UP claims the data is older than it
-- is, which is harmless, while rounding down would claim it is fresher, which is not.
function GC.Util.FormatElapsed(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds
      or seconds == math.huge or seconds == -math.huge or seconds < 0 then return nil end
  if seconds < 60 then return math.floor(seconds) .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  if seconds < 48 * 3600 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

-- A count, in the width a panel cell actually has. Small numbers stay exact because they
-- carry the decision -- three sales a day is the difference between a trade and a trap --
-- while a region-wide commodity's turnover does not: the check panel was printing
-- "856146.0", where both the trailing .0 and the last five digits were noise.
function GC.Util.FormatCount(value)
  if type(value) ~= "number" or value ~= value
      or value == math.huge or value == -math.huge or value < 0 then return nil end
  if value < 1000 then return tostring(math.floor(value + 0.5)) end
  if value < 1000000 then
    local thousands = value / 1000
    if thousands < 10 then return ("%.1fk"):format(math.floor(thousands * 10) / 10) end
    return math.floor(thousands + 0.5) .. "k"
  end
  local millions = value / 1000000
  if millions < 10 then return ("%.1fM"):format(math.floor(millions * 10) / 10) end
  return math.floor(millions + 0.5) .. "M"
end

-- ---------------------------------------------------------------------------
-- The throttled message system's "ready" flag, with an expiry.
--
-- C_AuctionHouse.IsThrottledMessageSystemReady() is false for a beat after every throttled
-- request, and every sender in this addon waited for it to turn true again -- or for
-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY, which is the same fact as an event. Observed on a live
-- client (2026-09-14): the flag stayed false for minutes with nothing of ours in flight,
-- Blizzard's own Browse answering searches the whole time, and the ready event never came.
-- The Sell tab sat at "PRICING…", the Deals scan never started. Blizzard's own UI never
-- consults the flag: a message sent while the system is busy is queued by the client
-- (AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED) and goes out when the slot frees.
--
-- So the flag is honoured for as long as a real request could still be pending, and no longer:
-- once it has been false for THROTTLE_STUCK_SECONDS the addon stops trusting it and paces
-- itself instead. A true flag clears the clock, so the ordinary beat-after-a-query case is
-- untouched.
--
-- ASKING and SPENDING are two calls, and that split is the fix for what shipped first. The
-- permit used to be handed out by ThrottleReady() itself, which meant it was spent by whoever
-- ASKED -- and every consumer here asks twice before it sends (the Sniper's ticker asks, then
-- the pre-warm it calls asks again 0 seconds into the window it just restarted and is told no),
-- while the one permit was global, so the consumer that happened to ask first starved the
-- other outright: the Sniper's arbiter runs immediately before the Sell tab's walk on every
-- ready event, and the Sell tab never got through. ThrottleReady() is now a pure read that
-- anybody may ask as often as they like, and ClaimThrottleSend(who) is what the code about to
-- call a Send*/Query* API asks -- once, per send, and fairly: one forced send per consumer per
-- window, never two within THROTTLE_CLAIM_SPACING of each other.
-- ---------------------------------------------------------------------------
GC.Util.THROTTLE_STUCK_SECONDS = 5
-- The shortest gap between two forced sends from DIFFERENT consumers. Without it the Sniper
-- and the Sell tab would both fire the instant the window opened, which is precisely the
-- back-to-back traffic the pacing exists to avoid.
GC.Util.THROTTLE_CLAIM_SPACING = 1
GC.Util.throttleStats = { queued = 0, dropped = 0, ready = 0, forced = 0 }
local notReadySince
local claimedAt = {} -- who -> when that consumer last forced a send under a stuck flag
local lastClaimAt    -- when ANY consumer last did

-- Timeline for `/gc board`: the last TRACE_CAP things the request slot and the Auto loop did,
-- with the client clock. Only what a human reading "why did it wait" needs -- a few entries
-- per second at most, never per tick.
local TRACE_CAP = 60
local trace = {}
function GC.Util.Trace(tag)
  local now = (GetTime or time)()
  trace[#trace + 1] = { at = now, tag = tag }
  if #trace > TRACE_CAP then table.remove(trace, 1) end
end
function GC.Util.TraceDump(n)
  n = n or TRACE_CAP
  local out = {}
  local first = math.max(1, #trace - n + 1)
  local base = trace[first] and trace[first].at or 0
  for i = first, #trace do
    out[#out + 1] = ("%6.2f %s"):format(trace[i].at - base, trace[i].tag)
  end
  return out
end

-- A pure read: whether a send is permitted right now. No side effect of any kind, so a
-- predicate can be asked at four ticks a second, by two consumers, without anybody's turn
-- being consumed by the asking.
function GC.Util.ThrottleReady()
  if not (C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady) then return false end
  if C_AuctionHouse.IsThrottledMessageSystemReady() then
    notReadySince = nil
    return true
  end
  local now = (GetTime or time)()
  if not notReadySince then
    notReadySince = now
    GC.Util.Trace("throttle: flag false, stuck clock started")
  end
  return (now - notReadySince) >= GC.Util.THROTTLE_STUCK_SECONDS
end

-- Asked by the code that is about to call a Send*/Query* API, and by nothing else. With the
-- flag true this is the flag, and nothing is paced. With the flag stuck it hands `who` one
-- forced send per THROTTLE_STUCK_SECONDS window, spaced at least THROTTLE_CLAIM_SPACING from
-- anybody else's -- so the Sniper's board and the Sell tab's pricing walk both keep moving on a
-- client whose flag has stopped meaning anything, instead of one of them taking every window.
function GC.Util.ClaimThrottleSend(who)
  if not (C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady) then return false end
  if C_AuctionHouse.IsThrottledMessageSystemReady() then
    notReadySince = nil
    return true
  end
  local now = (GetTime or time)()
  if not notReadySince then
    notReadySince = now
    GC.Util.Trace("throttle: flag false, stuck clock started")
  end
  if now - notReadySince < GC.Util.THROTTLE_STUCK_SECONDS then return false end
  if lastClaimAt and (now - lastClaimAt) < GC.Util.THROTTLE_CLAIM_SPACING then return false end
  who = who or "?"
  local mine = claimedAt[who]
  if mine and (now - mine) < GC.Util.THROTTLE_STUCK_SECONDS then return false end
  claimedAt[who], lastClaimAt = now, now
  GC.Util.throttleStats.forced = GC.Util.throttleStats.forced + 1
  GC.Util.Trace("throttle: forced send granted to " .. who .. " after " .. string.format("%.1f", now - notReadySince) .. "s stuck")
  return true
end

-- Event bookkeeping (Core/Init.lua routes the three events here): how the client has been
-- treating our messages, for `/gc sell`.
function GC.Util.NoteThrottleEvent(event)
  local stats = GC.Util.throttleStats
  if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED" then stats.queued = stats.queued + 1
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then stats.dropped = stats.dropped + 1
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then stats.ready = stats.ready + 1; notReadySince = nil
  end
  GC.Util.Trace("event: " .. tostring(event):gsub("AUCTION_HOUSE_THROTTLED_", ""))
end

-- Test seam: forget the not-ready clock and every consumer's claim with it.
function GC.Util._ResetThrottleClock()
  notReadySince, lastClaimAt = nil, nil
  for who in pairs(claimedAt) do claimedAt[who] = nil end
end
