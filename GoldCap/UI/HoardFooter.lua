local _, GC = ...

-- The GoldCap Hoard's footer, pinned at the window's foot under the selection bar's room
-- (UI/HoardFrame.lua's AddSection, loaded before this file with UI/HoardRow.lua and
-- UI/HoardList.lua), as the Window board draws it: Make room, Put back, and where the prices come
-- from.
-- - Make room moves every stack in the bags (the backpack, the four bags and the reagent bag) that
--   the bank the switch names takes, but a hearthstone, the biggest first (Core/Hoard.lua's
--   MakeRoom over the stacks the window's paint read, bound ones among them): into the character's own bank a soulbound one
--   too, into the Warband Bank a Warbound one but not a soulbound one, which it refuses (the
--   reader marks that one `stays`). When its run is over, what actually left the bags (the
--   window's run end, HF.Press's onRunEnd, heard once every stack the run sent has landed or been
--   given up, each with as many as left its slot) is remembered for the character at the keyboard,
--   added to what an earlier Make room into the same bank put there and Put back has not brought
--   back yet (Remember, SetRoom). It is disabled, its tooltip saying why, while what it put into the
--   other bank is not back (a room is one bank's, and a second one would lose the first), and while
--   it could not remember: a newer GoldCap's save, or a character whose name and realm the game has
--   not told yet.
-- - Put back takes that back out of that bank (PutBack), wherever the bags have room; when its run
--   is over, what came back is forgotten (Unreturned), the whole room once nothing is left: as many
--   of each stack as left the bank's slot, so a withdraw the bags had room for only part of keeps
--   the rest to put back. With nothing remembered, or with the switch on the other bank, it is
--   disabled and its tooltip says why, and which bank holds it.
-- - What is remembered is never more than its bank holds: whenever that bank can be read (each
--   paint at a bank where it can be used) every item is capped at what the bank holds of it now,
--   and the room forgotten once it holds none (Fit). Another character may have taken some out of
--   the Warband Bank, or the player all of it by hand. Not for the route's SETTLE_SECONDS after
--   Make room remembered it, though: a deposit's bank slot can show it a moment after the bags show
--   it gone, and a cap then would forget what went in. The cap is written only while no run goes
--   and every run over has been heard (HF.Settled): during a Put back a paint caps what it shows
--   and plans, but the stacks that have left the bank are taken off at the run's end, from the room
--   as it was stored, and the next paint caps and writes it. Writing the paint's cap would take
--   them off twice.
-- - The price line: where the prices GoldCap reads came from and how long ago, with a dot in the
--   kit's green while they are under FRESH_SECONDS old, amber after or with none.
-- Shown with a followed group, as the window's own part, and without one while Make room has
-- something to bring back.
--
-- Both buttons are the window's quiet move buttons (HF.ui.quietMove: their click is HF.Press, with
-- the run ids "footer:makeRoom" and "footer:putBack"), a pair as a row's Store and Take out are
-- (UI/HoardList.lua's PaintPair): while one's run goes it is its Stop where it stands and the other
-- gives way. Each is as wide as the wider of its words and Stop, and the footer keeps the room the
-- most its price line can need in the bank visit (every source and an age of each unit's widest
-- figure, measured at each paint), so nothing here moves under the cursor. This file paints from
-- what the window's paint read (ctx.inBags, ctx.inBank), writes what Make room put away
-- (GC.db.hoard, through Core/Hoard.lua), and reads no slot and moves nothing.
local HF = GC.HoardFrame
local K = GC.Kit.Tokens.color
local U = HF.ui
local L = U.L
local setText, colour, wrapping, heightOf, track = U.setText, U.colour, U.wrapping, U.heightOf, U.track

HF.Footer = {}
local HFF = HF.Footer
-- How long the prices count as fresh: the Companion sends the region's data every hour or so.
HFF.FRESH_SECONDS = 7200

-- In UI units; the boards are drawn at twice that. GAP: between the two buttons; LINE_GAP: between
-- the buttons and the price line, beside them or under them; DOT and DOT_GAP: the price line's dot
-- and the room right of it.
local M = { GAP = 4, LINE_GAP = 10, DOT = 6, DOT_GAP = 5 }

local function charNow()
  return GC.CraftClient.Char()
end

-- What Make room put away for `char`, as its bank holds it now, from that bank's stacks as the
-- window's paint read them (ctx.inBank): capped at them whenever they can be read (Core/Hoard.lua's
-- Fit), and kept so while every run has been heard (HF.Settled), forgotten once the bank holds none
-- of it; while a run goes the cap is only shown and planned with. For the route's SETTLE_SECONDS
-- after Make room remembered it nothing is capped: the bank's slot can show a deposit a moment
-- after the bags show it gone. Answers the room (nil for none) and that bank's stacks of its items
-- (nil while the bank cannot be read: then the room is as remembered).
local function roomNow(char, ctx)
  local H, route = GC.Hoard, GC.BankRoute
  local room = char and H.Room(GC.db, char) or nil
  if not (room and route.CanMove(room.bankType)) then return room, nil end
  local stacks = {}
  for _, stack in ipairs(ctx.inBank(room.bankType)) do
    if room.items[stack.itemID] then stacks[#stacks + 1] = stack end
  end
  if time() - room.at < route.SETTLE_SECONDS then return room, stacks end
  local fitted, changed = H.Fit(room, stacks)
  if changed and HF.Settled() then H.SetRoom(GC.db, char, fitted) end
  return fitted, stacks
end

-- Make room's run is over: what left the bags is remembered for the character, added to the room as
-- it was stored for the same bank; the next paint caps it at what that bank holds, once its slots
-- have had the time to show it. A run that moved nothing leaves the memory as it was.
local function onRoomMade(moved, bankType)
  local char = charNow()
  if not char or #moved == 0 then return end
  GC.Hoard.SetRoom(GC.db, char, GC.Hoard.Remember(bankType, time(), moved, GC.Hoard.Room(GC.db, char)))
end

-- Put back's run is over: what came back is taken off the room as it was stored (never capped while
-- the run went), the room forgotten once nothing is left of it; the next paint caps the rest at what
-- that bank holds.
local function onPutBack(moved)
  local char = charNow()
  if not char or #moved == 0 then return end
  GC.Hoard.SetRoom(GC.db, char, GC.Hoard.Unreturned(GC.Hoard.Room(GC.db, char), moved))
end

local function build(f)
  local T = GC.Theme
  f.makeRoom = U.quietMove(f, true, "footer:makeRoom")
  f.putBack = U.quietMove(f, false, "footer:putBack")
  f.makeRoom.onRunEnd, f.putBack.onRunEnd = onRoomMade, onPutBack
  -- The badge art is round at this size (T.LiveDot draws its light the same way).
  f.dot = f:CreateTexture(nil, "ARTWORK")
  f.dot:SetTexture(T.MEDIA .. "badge.png")
  f.dot:SetSize(M.DOT, M.DOT)
  f.prices = track(HF._frame, wrapping(T.Label(f, 9)))
  colour(f.prices, K.text3)
end

-- The price line's words for `origin` ("app", "manual" or "none") and an age in seconds.
local function pricesText(origin, age)
  if age and (origin == "app" or origin == "manual") then
    local ago = GC.Util.FormatElapsedWords(age) or ""
    return origin == "app" and GC.L["Prices from the Companion, %s ago"]:format(ago)
      or GC.L["You pasted these prices %s ago"]:format(ago)
  end
  return GC.L["No prices for your region yet"]
end

-- An age of each unit's widest figure, for the price line's room: what it can say later in the
-- visit is measured now.
local WIDEST_AGES = { 59, 59 * 60, 23 * 3600, 999 * 86400 }

-- Where the prices came from and how long ago, and whether that is fresh.
local function pricesNow()
  local origin = GC.Data.OriginState and GC.Data.OriginState() or "none"
  local ts = GC.db and GC.db.imported and GC.db.imported.ts
  local age = type(ts) == "number" and ts > 0 and math.max(0, time() - ts) or nil
  local known = age and (origin == "app" or origin == "manual")
  return pricesText(origin, age), known and age < HFF.FRESH_SECONDS or false
end

-- The Disenchant window's footer (UI/DisenchantFrame.lua) says the same line under the same dot.
HFF.PricesNow = pricesNow

-- Every line the price line can say in this visit: each source at each widest age, and none.
local function pricesVariants(text)
  local out = { text, pricesText("none") }
  for _, origin in ipairs({ "app", "manual" }) do
    for _, age in ipairs(WIDEST_AGES) do out[#out + 1] = pricesText(origin, age) end
  end
  return out
end

-- What Put back takes back, and what its tooltip says under its title: from the bank the switch
-- names when Make room put things there (`stacks`, that bank's, from roomNow), else nothing, with
-- why.
local function putBackPlan(room, stacks, ctx)
  if not room then return {}, GC.L["Make room has put nothing away to bring back."] end
  local bank = U.bankName(room.bankType)
  if room.bankType ~= ctx.bankType then
    return {}, GC.L["What Make room put away is in %s: switch to it to put it back."]:format(bank)
  end
  return GC.Hoard.PutBack(room, stacks or {}, ctx.moving),
    GC.L["Takes back from %s what Make room put there. It lands wherever your bags have room, not in its old slots."]:format(bank)
end

-- What Make room moves into the bank the switch names, and what its tooltip says: nothing, with
-- why, while it could not remember what went or while what it put into the other bank is not back.
local function makeRoomPlan(room, char, ctx)
  if not GC.Hoard.Writable(GC.db) then
    return {}, GC.L["A newer version of GoldCap saved what Make room remembers: update GoldCap to use it."]
  end
  if not char then
    return {}, GC.L["GoldCap does not know this character's name and realm yet, so Make room cannot remember what it puts away."]
  end
  if room and room.bankType ~= ctx.bankType then
    return {}, GC.L["What Make room put away is still in %s: put it back first."]:format(U.bankName(room.bankType))
  end
  return GC.Hoard.MakeRoom(ctx.inBags(), ctx.moving),
    GC.L["Moves every stack in your bags that %s takes, except a hearthstone, and remembers what went for Put back."]:format(U.bankName(ctx.bankType))
end

-- The two buttons on the footer's first line, then the price line beside them or under them, its
-- room kept for the visit. Answers the footer's height: it stands with no followed group too, as
-- Make room and Put back need none.
local function paint(f, ctx)
  local char = charNow()
  local room, stacks = roomNow(char, ctx)
  if f.visit ~= ctx.visit then f.visit, f.most, f.under = ctx.visit, 0, false end
  local back, backNote = putBackPlan(room, stacks, ctx)
  local make, makeNote = makeRoomPlan(room, char, ctx)
  local labels = { GC.L["Make room"], GC.L["Put back"] }
  local running = HF.List.PaintPair({
    { f.makeRoom, make, labels[1], makeNote },
    { f.putBack, back, labels[2], backNote },
  }, ctx.runId, true, ctx.run)
  for i, b in ipairs({ f.makeRoom, f.putBack }) do
    b:SetLabel(b == running and GC.L["Stop"] or labels[i])
    b:FitLabels({ labels[i], GC.L["Stop"] }, 0)
  end
  local makeW, backW = f.makeRoom:GetWidth(), f.putBack:GetWidth()
  f.makeRoom:ClearAllPoints()
  f.makeRoom:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.putBack:ClearAllPoints()
  f.putBack:SetPoint("TOPLEFT", f, "TOPLEFT", makeW + M.GAP, 0)

  local text, fresh = pricesNow()
  local c = fresh and K.profit or K.warn
  f.dot:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  local besideW = ctx.width - (makeW + M.GAP + backW) - M.LINE_GAP - M.DOT - M.DOT_GAP
  local underW = ctx.width - M.DOT - M.DOT_GAP
  -- Beside the buttons, ending at the footer's right, while every line it can say in this visit fits
  -- on one line there; else on a line of its own under them, wrapping, for the rest of the visit.
  f.prices:SetWidth(ctx.width)
  local variants = pricesVariants(text)
  local widest = 0
  for _, line in ipairs(variants) do
    setText(f.prices, line)
    widest = math.max(widest, math.ceil(f.prices:GetUnboundedStringWidth() or 0))
  end
  if widest > besideW then f.under = true end
  local oneLine = not f.under
  setText(f.prices, text)
  local fullW = math.ceil(f.prices:GetUnboundedStringWidth() or 0)
  local textW = oneLine and fullW or underW
  -- The room: the tallest line it can say, at the width it has.
  local textH = U.tallest(f.prices, variants, oneLine and widest or underW)
  f.prices:SetWidth(math.max(1, textW))
  setText(f.prices, text)
  local lineY = oneLine and math.floor((L.ALL_H - math.ceil(heightOf(f.prices, 12))) / 2) or (L.ALL_H + L.HEADING_GAP)
  local textX = oneLine and (ctx.width - textW) or (M.DOT + M.DOT_GAP)
  f.prices:ClearAllPoints()
  f.prices:SetPoint("TOPLEFT", f, "TOPLEFT", textX, -lineY)
  f.dot:ClearAllPoints()
  f.dot:SetPoint("TOPLEFT", f, "TOPLEFT", textX - M.DOT_GAP - M.DOT, -(lineY + math.floor((math.min(textH, 12) - M.DOT) / 2)))
  local h = oneLine and math.max(L.ALL_H, textH) or (lineY + textH)
  f.most = math.max(f.most, h)
  return f.most
end

HF.AddSection("footer", { build = build, paint = paint })
