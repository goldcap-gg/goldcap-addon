local _, GC = ...

-- The GoldCap Hoard's footer, pinned at the window's foot under the selection bar's room
-- (UI/HoardFrame.lua's AddSection, loaded before this file with UI/HoardRow.lua and
-- UI/HoardList.lua), as the Window board draws it: Make room, Put back, and where the prices come
-- from.
-- - Make room moves every stack in the bags (the backpack, the four bags and the reagent bag) that
--   the bank the switch names takes, the biggest first (Core/Hoard.lua's MakeRoom over the bank
--   route's reader), soulbound ones too into the character's own bank (the Warband Bank refuses
--   them). When its run is over, what actually left the bags (the window's run end, HF.Press's
--   onRunEnd) is remembered for the character at the keyboard, added to what an earlier Make room
--   into the same bank put there and Put back has not brought back yet (Remember, SetRoom).
-- - Put back takes that back out of that bank (PutBack), wherever the bags have room; when its run
--   is over, what came back is forgotten (Unreturned), the whole room once nothing is left. With
--   nothing remembered, or with the switch on the other bank, it is disabled and its tooltip says
--   why, and which bank holds it.
-- - The price line: where the prices GoldCap reads came from and how long ago, with a dot in the
--   kit's green while they are under FRESH_SECONDS old, amber after or with none.
-- Shown with a followed group, as the window's own part.
--
-- Both buttons are the window's move buttons (HF.ui.moveButton: their click is HF.Press, with the
-- run ids "footer:makeRoom" and "footer:putBack"), a pair as a row's Store and Take out are
-- (UI/HoardList.lua's PaintPair): while one's run goes it is its Stop where it stands and the other
-- gives way. Each is as wide as the wider of its words and Stop, and the footer keeps the room the
-- most its price line has needed in the bank visit, so nothing here moves under the cursor. This
-- file reads, paints and writes what Make room put away (GC.db.hoard, through Core/Hoard.lua), and
-- moves nothing.
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

local function everything() return true end

-- Make room's run is over: what left the bags is remembered for the character, added to an earlier
-- room in the same bank. A run that moved nothing leaves the memory as it was.
local function onRoomMade(moved, bankType)
  local char = charNow()
  if not char or #moved == 0 then return end
  GC.Hoard.SetRoom(GC.db, char, GC.Hoard.Remember(bankType, time(), moved, GC.Hoard.Room(GC.db, char)))
end

-- Put back's run is over: what came back is forgotten, the room once nothing is left of it.
local function onPutBack(moved)
  local char = charNow()
  if not char or #moved == 0 then return end
  GC.Hoard.SetRoom(GC.db, char, GC.Hoard.Unreturned(GC.Hoard.Room(GC.db, char), moved))
end

-- A quiet button, as Store all and Take all out are drawn: no fill, a faint ring, its words in the
-- second text colour.
local function quietButton(f, into, runId, onRunEnd)
  local b = U.moveButton(f, into, { variant = "segment", ring = K.windowBorder, textColor = K.text2 })
  b:SetHeight(L.ALL_H)
  b.runId, b.onRunEnd = runId, onRunEnd
  track(HF._frame, b.text)
  return b
end

local function build(f)
  local T = GC.Theme
  f.makeRoom = quietButton(f, true, "footer:makeRoom", onRoomMade)
  f.putBack = quietButton(f, false, "footer:putBack", onPutBack)
  -- The badge art is round at this size (T.LiveDot draws its light the same way).
  f.dot = f:CreateTexture(nil, "ARTWORK")
  f.dot:SetTexture(T.MEDIA .. "badge.png")
  f.dot:SetSize(M.DOT, M.DOT)
  f.prices = track(HF._frame, wrapping(T.Label(f, 9)))
  colour(f.prices, K.text3)
end

-- Where the prices came from and how long ago, and whether that is fresh.
local function pricesNow()
  local origin = GC.Data.OriginState and GC.Data.OriginState() or "none"
  local ts = GC.db and GC.db.imported and GC.db.imported.ts
  local age = type(ts) == "number" and ts > 0 and math.max(0, time() - ts) or nil
  if age and (origin == "app" or origin == "manual") then
    local ago = GC.Util.FormatElapsedWords(age) or ""
    local text = origin == "app" and GC.L["Prices from the Companion, %s ago"]:format(ago)
      or GC.L["You pasted these prices %s ago"]:format(ago)
    return text, age < HFF.FRESH_SECONDS
  end
  return GC.L["No prices for your region yet"], false
end

-- What Put back's tooltip says under its title, and what it takes back: from the bank the switch
-- names when Make room put things there, else nothing, with why.
local function putBackPlan(room, ctx)
  if not room then return {}, GC.L["Make room has put nothing away to bring back."] end
  local bank = U.bankName(room.bankType)
  if room.bankType ~= ctx.bankType then
    return {}, GC.L["What Make room put away is in %s: switch to it to put it back."]:format(bank)
  end
  local route = GC.BankRoute
  local function remembered(itemID) return room.items[itemID] ~= nil end
  local stacks = route.ReadStacks(route.BankTabs(ctx.bankType), true, remembered, ctx.bankType, { soulbound = true })
  return GC.Hoard.PutBack(room, stacks, ctx.moving),
    GC.L["Takes back from %s what Make room put there. It lands wherever your bags have room, not in its old slots."]:format(bank)
end

-- The two buttons on the footer's first line, then the price line beside them or under them, its
-- room kept for the visit. Answers the footer's height, 0 without a followed group.
local function paint(f, ctx)
  if not ctx.hasGroups then return 0 end
  local route, H = GC.BankRoute, GC.Hoard
  local character = Enum.BankType.Character
  local bagStacks = route.ReadStacks(U.BAGS, false, everything, ctx.bankType, { soulbound = ctx.bankType == character })
  local char = charNow()
  local room = char and H.Room(GC.db, char) or nil
  local back, backNote = putBackPlan(room, ctx)
  local bank = U.bankName(ctx.bankType)
  local labels = { GC.L["Make room"], GC.L["Put back"] }
  local running = HF.List.PaintPair({
    { f.makeRoom, H.MakeRoom(bagStacks, ctx.moving), labels[1],
      GC.L["Moves every stack in your bags that %s takes, and remembers what went for Put back."]:format(bank) },
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
  local buttonsW = makeW + M.GAP + backW
  local besideW = ctx.width - buttonsW - M.LINE_GAP - M.DOT - M.DOT_GAP
  -- Beside the buttons, ending at the footer's right, while it fits on one line there; else on a line
  -- of its own under them, wrapping.
  f.prices:SetWidth(ctx.width)
  setText(f.prices, text)
  local fullW = math.ceil(f.prices:GetUnboundedStringWidth() or 0)
  local oneLine = fullW <= besideW
  local textW = oneLine and fullW or (ctx.width - M.DOT - M.DOT_GAP)
  f.prices:SetWidth(math.max(1, textW))
  local textH = math.ceil(heightOf(f.prices, 12))
  local lineY = oneLine and math.floor((L.ALL_H - textH) / 2) or (L.ALL_H + L.HEADING_GAP)
  local textX = oneLine and (ctx.width - textW) or (M.DOT + M.DOT_GAP)
  f.prices:ClearAllPoints()
  f.prices:SetPoint("TOPLEFT", f, "TOPLEFT", textX, -lineY)
  f.dot:ClearAllPoints()
  f.dot:SetPoint("TOPLEFT", f, "TOPLEFT", textX - M.DOT_GAP - M.DOT, -(lineY + math.floor((math.min(textH, 12) - M.DOT) / 2)))
  local h = oneLine and math.max(L.ALL_H, textH) or (lineY + textH)
  if f.visit ~= ctx.visit then f.visit, f.most = ctx.visit, 0 end
  f.most = math.max(f.most, h)
  return f.most
end

HF.AddSection("footer", { pinned = true, build = build, paint = paint })
