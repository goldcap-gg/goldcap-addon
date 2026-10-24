local _, GC = ...

-- The GoldCap Hoard's carry cards, in the scroll under the groups (UI/HoardFrame.lua's AddSection,
-- loaded before this file with UI/HoardRow.lua and UI/HoardList.lua): what to carry between realms
-- through the Warband Bank (ClickUp 869fjhvn9), one blue card per row of the bank route's plan
-- (UI/BankRoute.lua's Plan, Core/SellRoute.lua's CarryPlan), as the Window board draws it: the
-- item's icon in its quality's edge, what to do with it ("Carry to another realm", "Take out to
-- sell here", or that the auction house refuses it), the item and how many, where it sells, for how
-- much and how soon (the route's WhereText, as /gc route says it), and its button: Put in, into the
-- Warband Bank, or Take out, out of it. Under the cards, what comes next. Shown only with something
-- to carry: a piece that cannot be sold is told beside one, never alone. goldcap.gg works out where
-- flips sell for retail realms alone, and without its region data there is no card and no slot is
-- read for one.
--
-- A card hands its item to another of the player's characters, which only the Warband Bank does: its
-- button names that bank whatever the window's switch says (HF.Press's bankType), and moves its
-- row's first stack, one per press, through the window's press (its run id
-- "carry:<itemID>:<bag>:<slot>:in" or ":out"); while that run goes the button is its Stop. This file
-- reads and paints and moves nothing. Pressed again and again in one spot, so a card shown in this
-- bank visit keeps its place and its height for the visit: one whose item has gone stays, its icon
-- checked and its button disabled, and a new one comes under the others.
local HF = GC.HoardFrame
local K = GC.Kit.Tokens.color
local U = HF.ui
local setText, colour, wrapping, heightOf, track = U.setText, U.colour, U.wrapping, U.heightOf, U.track

HF.Carry = {}

-- In UI units; the boards are drawn at twice that. PAD: a card's margin; ICON and ICON_GAP: the
-- item's icon and the room right of it; LINE_GAP between a card's lines; GAP between two cards;
-- BUTTON_H and BUTTON_GAP: its button and the room left of it; NOTE_GAP over the note.
local M = { PAD = 7, ICON = 22, ICON_GAP = 8, LINE_GAP = 2, GAP = 6, BUTTON_H = 21, BUTTON_GAP = 8, NOTE_GAP = 6 }
-- The board's blue: the kit's "yours", for what goes to another of the player's characters. A piece
-- that cannot be sold sits on the window's glass.
local CARD_FILL = { K.yours[1], K.yours[2], K.yours[3], 0.06 }
local CARD_RING = { K.yours[1], K.yours[2], K.yours[3], 0.25 }
local BUTTON_RING = { K.yours[1], K.yours[2], K.yours[3], 0.5 }
local KINDS = { "in", "out", "stuck" }

local function eyebrowOf(kind)
  if kind == "in" then return GC.L["Carry to another realm"] end
  if kind == "out" then return GC.L["Take out to sell here"] end
  return GC.L["Can't be sold"]
end

local function labelOf(kind)
  return kind == "in" and GC.L["Put in"] or GC.L["Take out"]
end

-- One card in the scroll (`f`, the section's frame). Its lines are tracked on the window and on the
-- card, for the redraw of either shown again.
local function newCard(f)
  local T, owner = GC.Theme, HF._frame
  local card = T.Card(f, CARD_FILL, CARD_RING, true)
  card.icon = HF.Row.NewIcon(card, M.ICON, false)
  card.eyebrow = track(owner, track(card, wrapping(T.Heading(card, 9))))
  card.name = track(owner, track(card, wrapping(T.Label(card, 11))))
  colour(card.name, K.text1)
  card.where = track(owner, track(card, wrapping(T.Label(card, 9))))
  colour(card.where, K.text3)
  card.button = U.moveButton(card, true, { variant = "yours", ring = BUTTON_RING })
  card.button.bankType = Enum.BankType.Account
  card.button:SetHeight(M.BUTTON_H)
  card.button:SetFrameLevel(card:GetFrameLevel() + 3)
  track(owner, track(card, card.button.text))
  card:Hide()
  return card
end

local function build(f)
  f.cards = {}
  f.note = track(HF._frame, wrapping(GC.Theme.Label(f, 9)))
  colour(f.note, K.text3)
end

-- The rows the plan has now, by key ("in:<itemID>"), and the keys of this visit in the order they
-- first came: a row the plan no longer has stays as it was last seen, done. New rows come only
-- beside something to carry.
local function rowsNow(f, ctx, plan)
  if f.visit ~= ctx.visit then f.visit, f.keys, f.last, f.room = ctx.visit, {}, {}, {} end
  local live = {}
  local lists = { ["in"] = plan.putIn, out = plan.takeOut, stuck = plan.stuck }
  local carrying = #plan.putIn + #plan.takeOut > 0
  for _, kind in ipairs(KINDS) do
    for _, row in ipairs(lists[kind]) do
      local key = kind .. ":" .. row.itemID
      live[key] = true
      if carrying and not f.last[key] then f.keys[#f.keys + 1] = key end
      if carrying or f.last[key] then f.last[key] = { kind = kind, row = row } end
    end
  end
  local entries = {}
  for _, key in ipairs(f.keys) do
    local entry = f.last[key]
    entries[#entries + 1] = { key = key, kind = entry.kind, row = entry.row, live = live[key] == true }
  end
  return entries
end

-- A card for `entry` at `y`, `width` wide: its lines, its icon (checked once its item has gone), and
-- its button over the row's first stack, the Stop of its own run. Answers its height, never lower
-- than it was in this visit.
local function paintCard(f, card, entry, ctx, y, width)
  local kind, row, live = entry.kind, entry.row, entry.live
  local stuck = kind == "stuck"
  card:SetTint(stuck and K.glassTop or CARD_FILL, stuck and K.glassBorder or CARD_RING)
  local mark = not live and "moved" or (ctx.marks and ctx.marks[row.itemID]) or nil
  HF.Row.PaintIcon(card.icon, row.itemID, row.icon, nil, not stuck and mark or nil)
  local b = card.button
  local buttonW = 0
  if stuck then
    b:Hide()
  else
    local stack = live and row.stacks[1] or nil
    local free = stack ~= nil and not stack.locked and not (ctx.moving and ctx.moving[GC.BankGroups.SlotKey(stack)])
    b.into = kind == "in"
    b.runId = stack and ("carry:%d:%d:%d:%s"):format(row.itemID, stack.bag, stack.slot, kind) or ("carry:" .. entry.key)
    local title = kind == "in" and GC.L["Put in the Warband Bank"] or GC.L["Take out to sell here"]
    local own = HF.List.PaintPair({ { b, free and { stack } or {}, title, GC.BankRoute.WhereText(kind, row.spot) } },
      ctx.runId, true, ctx.run) == b
    b:SetLabel(own and GC.L["Stop"] or labelOf(kind))
    b:FitLabels({ labelOf(kind), GC.L["Stop"] }, 0)
    buttonW = b:GetWidth() + M.BUTTON_GAP
  end
  local textX = M.PAD + M.ICON + M.ICON_GAP
  local textW = width - textX - M.PAD - buttonW
  local name = U.itemName({ name = row.name, itemID = row.itemID })
  if row.count > 1 then name = ("%s ×%d"):format(name, row.count) end
  local lineY = M.PAD
  for _, part in ipairs({ { card.eyebrow, GC.Util.Upper(eyebrowOf(kind)) }, { card.name, name },
    { card.where, GC.BankRoute.WhereText(kind, row.spot) } }) do
    local fs = part[1]
    fs:SetWidth(math.max(1, textW))
    setText(fs, part[2])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", textX, -lineY)
    lineY = lineY + math.ceil(heightOf(fs, 12)) + M.LINE_GAP
  end
  colour(card.eyebrow, stuck and K.text3 or K.yours)
  local h = math.max(M.ICON, M.BUTTON_H, lineY - M.LINE_GAP - M.PAD) + 2 * M.PAD
  h = math.max(h, f.room[entry.key] or 0)
  f.room[entry.key] = h
  card.icon.edge:ClearAllPoints()
  card.icon.edge:SetPoint("TOPLEFT", card, "TOPLEFT", M.PAD, -math.floor((h - M.ICON) / 2))
  if not stuck then
    b:ClearAllPoints()
    b:SetPoint("RIGHT", card, "RIGHT", -M.PAD, 0)
    b:Show()
  end
  card:ClearAllPoints()
  card:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
  card:SetSize(width, h)
  return h
end

-- The cards while the Warband Bank can be used here and the plan has something to carry (or had,
-- in this visit), then what comes next. Answers their height, 0 for none.
local function paint(f, ctx)
  local route = GC.BankRoute
  local entries = route.CanMove(Enum.BankType.Account) and rowsNow(f, ctx, route.Plan()) or {}
  local y, anyIn = 0, false
  for i, entry in ipairs(entries) do
    local card = f.cards[i] or newCard(f)
    f.cards[i] = card
    local wasUp = card:IsShown()
    card:Show()
    y = y + paintCard(f, card, entry, ctx, y, ctx.width) + M.GAP
    if not wasUp and HF._frame:IsShown() then U.restamp(card) end
    anyIn = anyIn or entry.kind == "in"
  end
  for i = #entries + 1, #f.cards do f.cards[i]:Hide() end
  if #entries == 0 then
    f.note:Hide()
    return 0
  end
  -- What comes next, for a player new to it: where the item goes after the bank.
  f.note:SetWidth(ctx.width)
  setText(f.note, anyIn and GC.L["Then log in a character on that realm and open a bank: GoldCap lists what to take out."]
    or GC.L["Then list it from GoldCap's Sell tab at the auction house."])
  f.note:ClearAllPoints()
  f.note:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(y - M.GAP + M.NOTE_GAP))
  f.note:Show()
  return y - M.GAP + M.NOTE_GAP + math.ceil(heightOf(f.note, 12))
end

HF.AddSection("carry", { build = build, paint = paint })
