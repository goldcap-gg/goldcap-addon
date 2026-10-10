local _, GC = ...

GC.Util = {}

-- WoW's string.format converts a %d/%i/%x/%c argument to a 32-bit integer and raises "integer
-- overflow attempting to store N" for anything outside +-2^31 (2,147,483,647 copper is about
-- 214,748g, and retail prices pass that routinely) -- a 1.5M-gold Forever troll listing crashed
-- a live scan on exactly this (Core/ForeverFold.lua's Encode). busted's own Lua has no such
-- ceiling, which is how it shipped behind a green suite; spec/support/wow_format.lua's shim is
-- what makes a spec able to catch it. %.0f has no ceiling either: it prints the same digits as
-- %d for any integer up to 2^53, the largest a Lua double still represents exactly -- more than
-- enough for any amount of copper this addon ever handles. Every %d/%i/%x whose argument can be
-- a copper amount, a price, a total, a deposit, or any other sum that can pass 214,748g goes
-- through this, not a bare string.format; counts, levels, percentages and indexes stay on %d,
-- since none of those can reach that range.
function GC.Util.IntText(n)
  return ("%.0f"):format(n)
end

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

-- A slash command's first word and the rest of the line, both trimmed. The word is returned as
-- typed; GC.OnSlash lowercases it to find the handler, and the rest goes to the handler untouched
-- (`/gc mount 12g 50s`, `/gc weights STR 1 STA 0.5`).
function GC.Util.SlashArgs(msg)
  if type(msg) ~= "string" then return "", "" end
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  return cmd or "", rest or ""
end

function GC.Util.FormatAge(seconds)
  if seconds < 3600 then return "<1h" end
  if seconds < 48 * 3600 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

-- Money with coin icons, in every client. Retail's global GetCoinTextureString renders this
-- today, so it is tried first -- byte-identical output there is the whole point. When it is
-- gone (WoW: Forever, probed 2026-09-24, where calling it throws), C_CurrencyInfo carries the
-- same texture-icon string; when neither exists this formats the same "12[g] 34[s] 56[c]"
-- shape itself. Every caller in the addon goes through here -- spec/coin_text_spec.lua fails
-- on a bare call.
local ICON = {
  g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
  s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
  c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
-- The same three coins, for a caller that lays an amount out itself (the Sell tab's figures).
GC.Util.COIN = ICON

-- A whole number grouped in thousands with the player's own separator: "98,470", and "98.470" in
-- a German client. The client's BreakUpLargeNumbers (both games) where it exists, a plain comma
-- grouping where it does not, which is the spec suite.
function GC.Util.Grouped(n)
  n = math.floor(n + 0.5)
  local fn = _G.BreakUpLargeNumbers
  if type(fn) == "function" then
    local ok, text = pcall(fn, n)
    if ok and text ~= nil then return tostring(text) end
  end
  local text, found = GC.Util.IntText(n), 1
  while found > 0 do text, found = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2") end
  return text
end

local function coinTextFallback(copper)
  -- Round first, sign the ROUNDED magnitude: a value that rounds to zero (e.g. -0.4) prints
  -- "0<copper icon>", never "-0<copper icon>".
  local magnitude = math.floor(math.abs(copper) + 0.5)
  local sign = (copper < 0 and magnitude > 0) and "-" or ""
  local gold = math.floor(magnitude / 10000)
  local silver = math.floor((magnitude % 10000) / 100)
  local rest = magnitude % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = GC.Util.IntText(gold) .. ICON.g end
  if silver > 0 then parts[#parts + 1] = ("%d%s"):format(silver, ICON.s) end
  if rest > 0 or #parts == 0 then parts[#parts + 1] = ("%d%s"):format(rest, ICON.c) end
  return sign .. table.concat(parts, " ")
end

function GC.Util.CoinText(copper)
  if type(_G.GetCoinTextureString) == "function" then return _G.GetCoinTextureString(copper) end
  local ci = _G.C_CurrencyInfo
  if ci and type(ci.GetCoinTextureString) == "function" then return ci.GetCoinTextureString(copper) end
  return coinTextFallback(copper)
end

-- Compact gold display: whole gold past 100g, gold+silver below it, a coin-icon string
-- under a gold. Moved here (Sniper fast loop, phase 1) from UI/SniperFrame.lua's own
-- formatColumnAmount so Core/BoardRows.lua can format a verdict label without a WoW frame --
-- the sub-gold case goes through GC.Util.CoinText above, so a caller without the client
-- (this addon's own spec suite) still gets a string back, exactly as every
-- UI/SniperFrame.lua spec already does.
local GOLD_COMPACT_THRESHOLD = 100 * 10000 -- 100g in copper
function GC.Util.FormatMoney(copper)
  if copper < 0 then return "-" .. GC.Util.FormatMoney(-copper) end
  if copper >= GOLD_COMPACT_THRESHOLD then
    return GC.Util.IntText(math.floor(copper / 10000)) .. "g"
  end
  if copper >= 10000 then
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if silver == 0 then return ("%dg"):format(gold) end
    return ("%dg%02ds"):format(gold, silver)
  end
  return GC.Util.CoinText(copper)
end

-- Whole gold, whole silver or whole copper: a context with room for ONE unit, never two, and no
-- coin icon (a plain string, for a FontString cell rather than a coin-texture readout). Sniper's
-- SAFE board label is the reason this exists -- FormatMoney's "61g35s" is two units wide, and the
-- 72px verdict cell it renders into clips it. Floors rather than rounds, same rule as
-- FormatAge/FormatElapsed above: a figure that rounds up promises gold the trade didn't clear.
-- The copper tier is WoW: Forever's (below).
function GC.Util.FormatGoldFloor(copper)
  if copper < 0 then return "-" .. GC.Util.FormatGoldFloor(-copper) end
  if copper >= 10000 then
    return GC.Util.IntText(math.floor(copper / 10000)) .. "g"
  end
  -- WoW: Forever's economy is copper: "SAFE +0s" on a 25c buy said nothing. Retail never gets
  -- here with a SAFE -- its profit floor is 1g (SniperDecision's normalizeConfig).
  if copper >= 100 then return ("%ds"):format(math.floor(copper / 100)) end
  return ("%dc"):format(math.floor(copper))
end

-- The gold a character must hold, rounded UP to whole gold: a figure that rounds down promises a
-- buy for less than the wallet limit lets through, and a player who fetches exactly that much is
-- refused anyway. The one formatter for it -- the Sniper's needs-gold cell, the check pane's
-- figure, caption and status line and the row tooltip all print the same figure through here.
-- `short` is for the cell, whose eleven characters cannot hold six digits: from 10,000g it counts
-- the same rounded-up gold in thousands, rounded up again, the way players write gold.
function GC.Util.FormatGoldCeil(copper, short)
  local gold = math.max(1, math.ceil(copper / 10000))
  if short and gold >= 10000 then return GC.Util.IntText(math.ceil(gold / 1000)) .. "k" end
  return GC.Util.IntText(gold) .. "g"
end

local MONEY_UNIT = { g = 10000, s = 100, c = 1 }

-- "12g 50s", "12g50s", "3s 20c", "90" (a bare number is gold, "0.5" half of one). nil for anything
-- else, and for zero: a price of nothing is not a price. Every price box in the addon reads
-- through this one (BUY's cap box, Road to 40's mount cost).
function GC.Util.ParseMoney(text)
  if type(text) ~= "string" then return nil end
  text = text:lower():gsub("%s+", "")
  if text == "" then return nil end
  local bare = text:match("^(%d+%.?%d*)$")
  if bare then
    local copper = math.floor(tonumber(bare) * 10000 + 0.5)
    return copper > 0 and copper or nil
  end
  local total, rest, seen = 0, text, {}
  while rest ~= "" do
    local num, unit, tail = rest:match("^(%d+)([gsc])(.*)$")
    if not num or seen[unit] then return nil end
    seen[unit] = true
    total = total + tonumber(num) * MONEY_UNIT[unit]
    rest = tail
  end
  return total > 0 and total or nil
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
local function elapsed(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds
      or seconds == math.huge or seconds == -math.huge or seconds < 0 then return nil end
  if seconds < 60 then return math.floor(seconds), "s" end
  if seconds < 3600 then return math.floor(seconds / 60), "m" end
  if seconds < 48 * 3600 then return math.floor(seconds / 3600), "h" end
  return math.floor(seconds / 86400), "d"
end

function GC.Util.FormatElapsed(seconds)
  local n, unit = elapsed(seconds)
  return n and n .. unit or nil
end

-- The unit letters of FormatElapsed, as the player's language writes them.
-- @localised-keys: literals in this table ARE GC.L keys, looked up in FormatElapsedWords.
local ELAPSED_UNIT = {
  s = "%ds", m = "%dm", h = "%dh", d = "%dd",
}

-- FormatElapsed's figure for a translated sentence ("last live price %s ago"): "3m" there is
-- English in eleven languages (final review m10, plan 3c). English reads exactly the same.
function GC.Util.FormatElapsedWords(seconds)
  local n, unit = elapsed(seconds)
  if not n then return nil end
  local key = ELAPSED_UNIT[unit]
  return ((GC.L and GC.L[key]) or key):format(n)
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

-- ---------------------------------------------------------------------------
-- The client's own words for what went wrong.
--
-- Blizzard's strings break paragraphs with |n, and every line that shows them here is one line
-- tall: word wrap off, so the second paragraph would draw over the first or not at all. Nil for
-- nothing worth saying, so a caller can fall back to its own sentence with `or`.
-- ---------------------------------------------------------------------------
function GC.Util.ClientLine(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("|n", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if text == "" then return nil end
  return text
end

-- ---------------------------------------------------------------------------
-- Text for a widget the CLIENT's font draws: a MenuUtil menu, a tooltip, the chat frame, a
-- Blizzard template, a Theme.Label (UI/Theme.lua's ClientFont routes those). The client's
-- faces miss glyphs GoldCap's own faces have, and a missing glyph draws as an empty box. GoldCap's
-- own are the bundled Fira faces (Fira Mono has · → ▲ ▼; Fira Sans and Fira Sans Condensed have ·
-- → and no triangles, so their text goes through GC.Util.ClientText).
--
-- Seen in game, 2026-10-01, Russian client: the BUY list menu read "• Quick list [] 2 lines
-- [] pasted" -- the bullet drawn, every middle dot a box. What the faces hold was then read
-- from the client's own font cache (Fonts/<id>.slug, its code point table), not guessed:
--   FRIZQT___CYR (menus, tooltips and labels on a Russian client): no U+00B7 ·, U+2192 →,
--     U+2212 −, U+2248 ≈, U+25B2 ▲, U+25BC ▼, U+25BE ▾, U+25B8 ▸ or U+21B3 ↳.
--   FRIZQT__ (the same widgets on every Latin client): has · − ≈; none of → ▲ ▼ ▾ ▸ ↳.
--   Both have • — – … × « » „ “ ” ’ ¿, which therefore pass untouched.
-- The chat face (ARIALN) and the Chinese tooltip faces are not in that cache and could not be
-- read; what reaches them is respelled the same way rather than trusted.
--
-- So: a middle dot BETWEEN SPACES is a separator and becomes ", ". One inside a word is left
-- alone -- that is how Chinese writes a transliterated name, and the Chinese faces have it. The
-- arrow becomes "->", and the triangles -- GoldCap only writes them in front of a percentage --
-- "+" and "-" (TriangleText below, which GoldCap's own Fira faces use on its own: they hold · and
-- →). − ≈ ▾ ▸ ↳ are no longer in GoldCap's text at all (spec/client_text_spec.lua's glyph
-- inventory keeps it that way), so they need no entry here.
-- ---------------------------------------------------------------------------
local TRIANGLE_GLYPHS = {
  { "\226\150\178", "+" }, -- U+25B2 ▲
  { "\226\150\188", "-" }, -- U+25BC ▼
}

--- Only the two triangles respelled ("+" and "-"), for text drawn by a face that has everything
-- else GoldCap writes: GoldCap's own Fira faces hold · → ≈ − and lack just ▲ and ▼.
function GC.Util.TriangleText(text)
  if type(text) ~= "string" or not text:find("\226", 1, true) then return text end
  for _, pair in ipairs(TRIANGLE_GLYPHS) do
    if text:find(pair[1], 1, true) then text = text:gsub(pair[1], pair[2]) end
  end
  return text
end

--- All of the respelling above, for text drawn by one of the client's own faces.
function GC.Util.ClientText(text)
  -- Every glyph handled here starts with one of these two bytes: ASCII and Cyrillic skip.
  if type(text) ~= "string" or not text:find("[\194\226]") then return text end
  text = text:gsub("%s+\194\183%s+", ", ")
  text = text:gsub("\226\134\146", "->")
  return GC.Util.TriangleText(text)
end

-- The Sold tab's tooltips were written against this name; one implementation, two names.
GC.Util.TooltipText = GC.Util.ClientText

-- AUCTION_HOUSE_SHOW_ERROR carries an Enum.AuctionHouseError. The default UI prints
-- AuctionHouseUtil.GetErrorText(error) for it (Blizzard_AuctionHouseFrame.lua's OnEvent), and
-- that lookup answers "" for a code it has no text for. The table lives in the auction house's
-- own load-on-demand addon, which is loaded whenever the auction house is open -- the only time
-- this event fires -- but a missing or broken one reads as "no words", never an error.
function GC.Util.AuctionHouseErrorText(code)
  local util = _G.AuctionHouseUtil
  if type(util) ~= "table" or type(util.GetErrorText) ~= "function" then return nil end
  local ok, text = pcall(util.GetErrorText, code)
  return ok and GC.Util.ClientLine(text) or nil
end
