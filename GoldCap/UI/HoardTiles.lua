local _, GC = ...

-- The GoldCap Hoard's tiles ("Ready now"), pinned under the bank switch (UI/HoardFrame.lua's
-- AddSection, loaded before this file with UI/HoardRow.lua and UI/HoardList.lua): three presses that
-- do the right thing now without a TSM operation, each a tile with its items' icons, its name, one
-- line and its button, as the Window board draws them.
-- - Prices are up: the followed groups' stacks in the bank chosen whose market value is at least
--   PRICE_UP_PCT of their group's usual price, taken out for the Sell tab (Core/Hoard.lua's
--   PricesUp).
-- - For your crafts: what the craft queue of the character at the keyboard needs and the bags lack
--   (UI/CraftQueueView.lua's Needs, Core/CraftQueue.lua's Missing over the bags alone), as the
--   fewest whole stacks of the bank chosen that cover it (ForCrafts).
-- - Put away: every group's Store list, keep counts held, less what Prices are up would sell from
--   the bags and the reagents the queue needs (PutAway).
-- Each button's tooltip lists what it moves and says what comes after. From SEARCH_MIN_GROUPS
-- groups, as the search row shows, the tiles are the ManyGroups board's compact strip: each tile one
-- button with two icons, its name, how much, and a chevron.
--
-- Every press is the window's (the buttons are HF.ui.moveButton's: their click is HF.Press, with the
-- run ids "tile:pricesUp", "tile:forCrafts" and "tile:putAway"); this file reads and paints and
-- moves nothing. Pressed again and again in one spot, so nothing here moves under the cursor: a tile
-- with nothing to do is dimmed, its button disabled, and keeps its place; the three are as tall as
-- the most any of their words can say in the player's language (every line and label a tile can
-- show, measured at each paint, and never lower in the bank visit), so a press, a run and its end
-- leave every tile where it was. While a run goes the tiles dim and take no click, except the one
-- whose press it is: its button is its Stop where it stands (UI/HoardList.lua's PaintPair) and its
-- line says how far the run is. No word is cut: a title, a line and a label wrap inside the tile.
local HF = GC.HoardFrame
local K = GC.Kit.Tokens.color
local U = HF.ui
local L = U.L
local setText, colour, wrapping, heightOf, track = U.setText, U.colour, U.wrapping, U.heightOf, U.track

-- In UI units; the boards are drawn at twice that. GAP: between two tiles. PAD: a tile's margin.
-- ICON, OVERLAP: a full tile's icons and how far each lies over the one before; ICON_GAP, TITLE_GAP,
-- BUTTON_GAP: under the icons, the title and the line. BUTTON_H, LABEL_PAD: the button's least
-- height, and its words' room from its sides and its top and bottom. COMPACT_*: the strip's tiles
-- (its least height, margin, icons and gaps), CHEVRON its arrow. TIP_ROWS: the most items a tooltip
-- lists before "and N more".
local M = {
  GAP = 6, PAD = 8, ICON = 20, OVERLAP = 6, ICON_GAP = 6, TITLE_GAP = 3, BUTTON_GAP = 8, BUTTON_H = 20,
  LABEL_PAD = 6, LABEL_VPAD = 4, COMPACT_H = 38, COMPACT_PAD = 7, COMPACT_ICON = 16, COMPACT_GAP = 6, CHEVRON = 8,
  TIP_ROWS = 12,
}
local ORDER = { "pricesUp", "forCrafts", "putAway" }
-- Prices are up in the board's gold, its button the gold fill, while it has something to take out;
-- the other two, and Prices are up with nothing, on the window's glass, their buttons in a gold
-- tint and ring.
local UP_FILL = { K.gold[1], K.gold[2], K.gold[3], 0.08 }
local UP_RING = { K.gold[1], K.gold[2], K.gold[3], 0.55 }
local MOVE_RING = { K.gold[1], K.gold[2], K.gold[3], 0.45 }
-- A button's look at rest (UI/HoardFrame.lua's moveButton), a full tile's and a compact one's, in
-- Prices are up's gold or as the other two wear it.
local function fullLook(gold)
  return gold and { variant = "primary" } or { variant = "active", ring = MOVE_RING }
end
local function compactLook(gold)
  return { variant = gold and "active" or "ghost", ring = gold and UP_RING or K.glassBorder, icon = "caretRight",
    iconColor = gold and K.goldText or K.text2 }
end
-- A tile with nothing to do, or while another press's run goes: the board's 45%.
local DIM = 0.45
-- The count a line or a label is measured with besides its own, so a count that changes does not
-- make a tile taller (one past it can, once in a visit: the room is measured at the paint that
-- shows it, never after). MOST_WORTH the same for Prices are up's worth: the gold cap.
local MOST = 99
local MOST_WORTH = 9999999 * 10000

-- ---------------------------------------------------------------------------------------------
-- What each tile moves
-- ---------------------------------------------------------------------------------------------

-- An item's usual price at `itemLevel` (a stack's): its group's (Core/GroupRules.lua), nil without
-- one, and nil for a piece of gear under the level its group's cap was priced at. For one paint:
-- asked of the group rules once per item and level, however many stacks and tiles ask.
local function usualsOnce()
  local seen = {}
  return function(itemID, itemLevel)
    local at = itemID .. ":" .. tostring(itemLevel or 0)
    local usual = seen[at]
    if usual == nil then
      local rule = GC.GroupRules.RuleFor(itemID, itemLevel)
      usual = rule and rule.usualUnit or false
      seen[at] = usual
    end
    return usual or nil
  end
end

-- What the craft queue of the character at the keyboard needs in all, and how many crafts that is.
local function craftNeeds()
  local char = GC.CraftClient.Char()
  if not char then return {}, 0 end
  return GC.CraftQueueView.Needs(char)
end

-- For your crafts: the queue's needs counted against the bags alone, every quality of a reagent and
-- the bound ones too, and what the bank chosen has of them: of the stacks the window's paint read
-- (ctx.inBags, ctx.inBank), no slot read here.
local function forCrafts(ctx, needs)
  local want = {}
  for _, row in ipairs(needs) do
    for _, id in ipairs(row.ids or {}) do want[id] = true end
  end
  if next(want) == nil then return { stacks = {}, items = {} } end
  local inBags = {}
  for _, stack in ipairs(ctx.inBags()) do
    if want[stack.itemID] then inBags[stack.itemID] = (inBags[stack.itemID] or 0) + stack.count end
  end
  local missing = GC.CraftQueue.Missing(needs, function(id) return inBags[id] or 0 end, GC.CraftClient.CurrencyCount)
  local bank = {}
  for _, stack in ipairs(ctx.inBank(ctx.bankType)) do
    if want[stack.itemID] then bank[#bank + 1] = stack end
  end
  return GC.Hoard.ForCrafts(missing, bank, ctx.moving)
end

-- The three plans over what the window read (the followed groups' stacks in the bags and the bank
-- chosen, and its plan), and how many crafts the queue has. Put away leaves out every quality of
-- what the queue needs, and each stack in the bags that sells above its usual price at its own
-- item level.
local function plansFor(ctx)
  local H = GC.Hoard
  local needs, crafts = craftNeeds()
  local usualOf = usualsOnce()
  local reagents, up = {}, {}
  for _, row in ipairs(needs) do
    for _, id in ipairs(row.ids or {}) do reagents[id] = true end
  end
  for _, stack in ipairs(ctx.bagStacks) do
    if H.IsPriceUp(stack.itemID, ctx.valueOf, usualOf, stack.ilvl) then up[GC.BankGroups.SlotKey(stack)] = true end
  end
  return {
    pricesUp = H.PricesUp(ctx.bankStacks, { groupOf = GC.GroupRules.GroupOf, valueOf = ctx.valueOf, usualOf = usualOf,
      moving = ctx.moving }),
    forCrafts = forCrafts(ctx, needs),
    putAway = H.PutAway(ctx.groups, reagents, up),
  }, crafts
end

-- Each item's icon, from the first of its stacks in `plan`.
local function iconsOf(plan)
  local icons = {}
  for _, stack in ipairs(plan.stacks) do
    if icons[stack.itemID] == nil then icons[stack.itemID] = stack.icon end
  end
  return icons
end

-- ---------------------------------------------------------------------------------------------
-- Words
-- ---------------------------------------------------------------------------------------------

local function titleOf(id)
  if id == "pricesUp" then return GC.L["Prices are up"] end
  if id == "forCrafts" then return GC.L["For your crafts"] end
  return GC.L["Put away"]
end

-- A tile's line for `n` (Prices are up: items up; For your crafts: crafts in the queue).
local function lineOf(id, n)
  if id == "pricesUp" then
    if n == 0 then return GC.L["Nothing sells above your usual price now"] end
    if n == 1 then return GC.L["1 item sells above your usual price"] end
    return GC.L["%d items sell above your usual price"]:format(n)
  elseif id == "forCrafts" then
    if n == 0 then return GC.L["Your craft queue is empty"] end
    if n == 1 then return GC.L["Reagents for the craft in your queue"] end
    return GC.L["Reagents for the %d crafts in your queue"]:format(n)
  end
  return GC.L["What you are not selling now, keeping what each group keeps"]
end

-- Store or Take out with how many stacks.
local function stacksLabel(into, n)
  if into then
    if n == 0 then return GC.L["Store"] end
    if n == 1 then return GC.L["Store 1 stack"] end
    return GC.L["Store %d stacks"]:format(n)
  end
  if n == 0 then return GC.L["Take out"] end
  if n == 1 then return GC.L["Take out 1 stack"] end
  return GC.L["Take out %d stacks"]:format(n)
end

-- A full tile's button: Prices are up's with the worth it takes out.
local function labelOf(id, plan)
  if id == "pricesUp" then
    return plan.worth > 0 and GC.L["Take out %s"]:format(U.worthText(plan.worth)) or GC.L["Take out"]
  end
  return stacksLabel(id == "putAway", #plan.stacks)
end

-- Every label a full tile's button can say, for its room.
local function labelsOf(id, plan)
  local labels = { labelOf(id, plan), GC.L["Stop"] }
  if id == "pricesUp" then
    labels[3], labels[4] = GC.L["Take out"], GC.L["Take out %s"]:format(U.worthText(MOST_WORTH))
  else
    for _, n in ipairs({ 0, 1, MOST }) do labels[#labels + 1] = stacksLabel(id == "putAway", n) end
  end
  return labels
end

-- A compact tile's second line: Prices are up's worth, the others' stacks.
local function subOf(id, plan)
  if #plan.stacks == 0 then return GC.L["Nothing to move"] end
  if id == "pricesUp" then return U.worthText(plan.worth) end
  return #plan.stacks == 1 and GC.L["1 stack"] or GC.L["%d stacks"]:format(#plan.stacks)
end

-- ---------------------------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------------------------

local function line(tooltip, text, c, wrap)
  tooltip:AddLine(GC.Util.ClientText(text), c[1], c[2], c[3], wrap)
end

-- The items a press moves, a row each with its icon (`icons`), at most TIP_ROWS, then how many more:
-- "name ×count", or with `right(item)` at the row's right.
local function itemRows(tooltip, items, icons, right)
  for i, item in ipairs(items) do
    if i > M.TIP_ROWS then
      line(tooltip, GC.L["and %d more"]:format(#items - M.TIP_ROWS), K.text3)
      return
    end
    local left = ("|T%s:0|t "):format(tostring(icons[item.itemID] or 134400)) .. U.itemName(item)
    if item.count then left = left .. (" ×%d"):format(item.count) end
    if right then
      tooltip:AddDoubleLine(GC.Util.ClientText(left), GC.Util.ClientText(right(item)), K.text1[1], K.text1[2], K.text1[3],
        K.text2[1], K.text2[2], K.text2[3])
    else
      line(tooltip, left, K.text1)
    end
  end
end

-- What each tile's press moves, under its title: what the tile is, the items, and what comes after.
local TIPS = {
  pricesUp = function(tooltip, button)
    local plan = button.plan
    line(tooltip, GC.L["These sell above the usual price you set for their group."], K.text2, true)
    if #plan.stacks == 0 then return line(tooltip, GC.L["Nothing to move"], K.text3) end
    line(tooltip, GC.L["Price per unit: now / usual"], K.text3)
    itemRows(tooltip, plan.items, iconsOf(plan), function(item)
      return GC.Util.Colored(K.profit, GC.Util.Money(item.now)) .. GC.Util.Colored(K.text3, " / " .. GC.Util.Money(item.usual))
    end)
    line(tooltip, GC.L["Worth about %s"]:format(GC.Util.Colored(K.goldText, U.worthText(plan.worth))), K.text1)
    line(tooltip, GC.L["Takes them out to your bags, ready for the Sell tab."], K.profit, true)
  end,
  forCrafts = function(tooltip, button)
    local plan = button.plan
    line(tooltip, GC.L["What your craft queue needs that your bags lack, from this bank."], K.text2, true)
    if #plan.stacks == 0 then return line(tooltip, GC.L["Nothing to move"], K.text3) end
    line(tooltip, GC.L["Per reagent: need / in bags / taken"], K.text3)
    itemRows(tooltip, plan.items, iconsOf(plan), function(item)
      return ("%d / %d / %d"):format(item.need, item.inBags, item.taken)
    end)
    line(tooltip, U.stacksInto(#plan.stacks), K.text1)
  end,
  putAway = function(tooltip, button)
    local plan, n = button.plan, #button.plan.stacks
    line(tooltip, GC.L["Leaves out what sells above its usual price and what your craft queue needs."], K.text2, true)
    if n == 0 then return line(tooltip, GC.L["Nothing to move"], K.text3) end
    itemRows(tooltip, plan.items, iconsOf(plan))
    line(tooltip, U.stacksInto(n, U.bankName(button.bankShown)), K.text1)
  end,
}

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

-- `n` item icons on `parent`, each in a holder of its own so the first lies over the next, as the
-- board overlaps them; an icon is UI/HoardRow.lua's (its quality's edge).
local function newIcons(parent, n, size)
  local icons = {}
  for i = 1, n do
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder:SetFrameLevel(parent:GetFrameLevel() + 1 + n - i)
    holder.slot = HF.Row.NewIcon(holder, size, false)
    holder.slot.edge:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    icons[i] = holder
  end
  return icons
end

local function paintIcons(icons, plan, x, y, size, parent)
  local items, byIcon = {}, iconsOf(plan)
  for _, stack in ipairs(plan.stacks) do
    if #items == #icons then break end
    local seen = false
    for _, id in ipairs(items) do seen = seen or id == stack.itemID end
    if not seen then items[#items + 1] = stack.itemID end
  end
  for i, holder in ipairs(icons) do
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (size - M.OVERLAP), -y)
    if items[i] then
      HF.Row.PaintIcon(holder.slot, items[i], byIcon[items[i]], nil, nil)
      holder:Show()
    else
      HF.Row.HideIcon(holder.slot)
      holder:Hide()
    end
  end
end

-- A full tile: its card (in Prices are up's gold, else the glass), its three icons, its title, its
-- line and, in the line's place while its run goes, the run's cast bar, and its button across its
-- foot, whose words wrap inside it.
local function newFull(f, id)
  local T, owner = GC.Theme, HF._frame
  local gold = id == "pricesUp"
  local t = { id = id }
  t.card = T.Card(f, gold and UP_FILL or K.glassTop, gold and UP_RING or K.glassBorder, true)
  t.icons = newIcons(t.card, 3, M.ICON)
  t.title = track(owner, wrapping(T.Heading(t.card, 11)))
  colour(t.title, K.text1)
  t.line = track(owner, wrapping(T.Label(t.card, 9)))
  colour(t.line, K.text3)
  t.cast = HF.List.NewCast(t.card, owner, 9, true)
  t.button = U.moveButton(t.card, id == "putAway", fullLook(gold))
  t.button:SetFrameLevel(t.card:GetFrameLevel() + 5)
  t.button.runId = "tile:" .. id
  t.button.tipLines = TIPS[id]
  t.button.text:SetWordWrap(true)
  t.button.text:SetMaxLines(3)
  track(owner, t.button.text)
  return t
end

-- A compact tile: the whole tile is its button, with two icons, its title, how much, and the kit's
-- chevron at its right, where its Stop wears the kit's close glyph, as an icon button's does
-- (UI/HoardList.lua's PaintPair).
local function newCompact(f, id)
  local T, owner = GC.Theme, HF._frame
  local gold = id == "pricesUp"
  local t = { id = id }
  t.button = U.moveButton(f, id == "putAway", compactLook(gold))
  t.card = t.button
  t.button.runId = "tile:" .. id
  t.button.tipLines = TIPS[id]
  t.button.icon:SetSize(M.CHEVRON, M.CHEVRON)
  t.button.icon:SetPoint("RIGHT", t.button, "RIGHT", -M.COMPACT_PAD, 0)
  t.icons = newIcons(t.button, 2, M.COMPACT_ICON)
  t.title = track(owner, wrapping(T.Heading(t.button, 10)))
  colour(t.title, K.text1)
  t.sub = track(owner, wrapping(gold and T.Num(t.button, 9) or T.Label(t.button, 9)))
  colour(t.sub, gold and K.goldText or K.text3)
  t.cast = HF.List.NewCast(t.button, owner, 9)
  t.button:Hide()
  return t
end

local function build(f)
  local T = GC.Theme
  f.heading = track(HF._frame, T.Heading(f, 9))
  f.heading:SetWordWrap(false)
  colour(f.heading, K.text3)
  -- Measures what a button's words need; never shown.
  f.measure = wrapping(T.Heading(f, 10))
  f.measure:Hide()
  f.full, f.compact = {}, {}
  for _, id in ipairs(ORDER) do
    f.full[id] = newFull(f, id)
    f.compact[id] = newCompact(f, id)
  end
end

-- ---------------------------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------------------------

-- The room each part keeps for the bank visit: never less than it was, so nothing moves.
local function keep(f, ctx, room)
  if f.visit ~= ctx.visit then f.visit, f.room = ctx.visit, {} end
  for k, v in pairs(room) do f.room[k] = math.max(f.room[k] or 0, v) end
  return f.room
end

-- A tile's button for its plan, as a pair of one (UI/HoardList.lua's PaintPair): what it moves, its
-- Stop while its own run goes; disabled while another press's run goes. The tile dims with nothing
-- to do and under another run. Answers whether its own run goes.
-- Prices are up wears the board's gold only while it has something to take out, or its run goes.
-- Empty, it is dimmed as the other two are: gold there still asked for a press that does nothing
-- (owner 2026-10-25). Worn again only when that changes, and not over its Stop.
local function wearGold(t, plan, ctx, compact)
  if t.id ~= "pricesUp" then return end
  local button = t.button
  local gold = #plan.stacks > 0 or (ctx.runId ~= nil and ctx.runId == button.runId)
  if t.gold == gold then return end
  t.gold = gold
  button.look = compact and compactLook(gold) or fullLook(gold)
  button.iconColor = button.look.iconColor
  if not button.stopping then
    button:SetVariant(button.look.variant)
    button:SetRing(button.look.ring)
  end
  if compact then
    colour(t.sub, gold and K.goldText or K.text3)
  else
    t.card:SetTint(gold and UP_FILL or K.glassTop, gold and UP_RING or K.glassBorder)
  end
end

local function paintTileButton(t, plan, ctx, compact)
  local button = t.button
  wearGold(t, plan, ctx, compact)
  button.plan, button.bankShown = plan, ctx.bankType
  local own = HF.List.PaintPair({ { button, plan.stacks, titleOf(t.id) } }, ctx.runId, true, ctx.run) == button
  local other = ctx.running and not own
  if other then button:Disable() end
  t.card:SetAlpha((other or (#plan.stacks == 0 and not own)) and DIM or 1)
  return own
end

-- The full tiles, `w` wide each, under the heading: the same room for the three.
local function paintFull(f, plans, crafts, ctx, w)
  local inner, labelW = w - 2 * M.PAD, w - 2 * M.PAD - 2 * M.LABEL_PAD
  setText(f.heading, GC.Util.Upper(GC.L["Ready now"]))
  f.heading:ClearAllPoints()
  f.heading:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.heading:Show()
  local top = math.ceil(heightOf(f.heading, 12)) + L.HEADING_GAP
  local titleH, lineH, labelH = 0, 0, 0
  for _, id in ipairs(ORDER) do
    local t, plan = f.full[id], plans[id]
    titleH = math.max(titleH, U.tallest(t.title, { titleOf(id) }, inner))
    local lines = id == "putAway" and { lineOf(id) } or { lineOf(id, 0), lineOf(id, 1), lineOf(id, MOST) }
    lineH = math.max(lineH, U.tallest(t.line, lines, inner), HF.List.LineCastHeight(t.cast, ctx.castLabels, inner))
    labelH = math.max(labelH, U.tallest(f.measure, labelsOf(id, plan), labelW))
  end
  local room = keep(f, ctx, { title = titleH, line = lineH, button = math.max(M.BUTTON_H, labelH + 2 * M.LABEL_VPAD) })
  local titleY = M.PAD + M.ICON + M.ICON_GAP
  local lineY = titleY + room.title + M.TITLE_GAP
  local h = lineY + room.line + M.BUTTON_GAP + room.button + M.PAD
  for i, id in ipairs(ORDER) do
    local t, plan = f.full[id], plans[id]
    t.card:ClearAllPoints()
    t.card:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (w + M.GAP), -top)
    t.card:SetSize(w, h)
    t.card:Show()
    paintIcons(t.icons, plan, M.PAD, M.PAD, M.ICON, t.card)
    setText(t.title, titleOf(id))
    t.title:ClearAllPoints()
    t.title:SetPoint("TOPLEFT", t.card, "TOPLEFT", M.PAD, -titleY)
    setText(t.line, lineOf(id, id == "pricesUp" and #plan.items or crafts))
    t.line:ClearAllPoints()
    t.line:SetPoint("TOPLEFT", t.card, "TOPLEFT", M.PAD, -lineY)
    local button = t.button
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", t.card, "BOTTOMLEFT", M.PAD, M.PAD)
    button:SetSize(inner, room.button)
    local own = paintTileButton(t, plan, ctx)
    button:SetLabel(own and GC.L["Stop"] or labelOf(id, plan))
    -- The kit bounds a label at the button's edges on one line (UI/Kit/Button.lua's SetLabel): here
    -- it keeps a margin and wraps.
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", button, "LEFT", M.LABEL_PAD, 0)
    button.text:SetPoint("RIGHT", button, "RIGHT", -M.LABEL_PAD, 0)
    button.text:SetWidth(labelW)
    t.line:SetShown(not own)
    if own then
      HF.List.PaintLineCast(t.cast, ctx.run, t.card, M.PAD, lineY, inner)
    else
      HF.List.HideCast(t.cast)
    end
  end
  return top + h
end

-- The compact strip, `w` wide each: the same height for the three.
local function paintCompact(f, plans, ctx, w)
  f.heading:Hide()
  local textX = M.COMPACT_PAD + 2 * M.COMPACT_ICON - M.OVERLAP + M.COMPACT_GAP
  local textW = w - textX - M.COMPACT_GAP - M.CHEVRON - M.COMPACT_PAD
  local titleH, subH, countH = 0, 0, 0
  for _, id in ipairs(ORDER) do
    local t, plan = f.compact[id], plans[id]
    titleH = math.max(titleH, U.tallest(t.title, { titleOf(id) }, textW))
    local subs = { subOf(id, plan), GC.L["Nothing to move"] }
    if id == "pricesUp" then
      subs[3] = U.worthText(MOST_WORTH)
    else
      subs[3], subs[4] = GC.L["1 stack"], GC.L["%d stacks"]:format(MOST)
    end
    setText(t.cast.count, ("%d / %d"):format(MOST, MOST))
    countH = math.max(countH, math.ceil(heightOf(t.cast.count, 12)))
    subH = math.max(subH, U.tallest(t.sub, subs, textW), countH + 2 + L.FILL_H)
  end
  local room = keep(f, ctx, { compactTitle = titleH, sub = subH })
  local h = math.max(M.COMPACT_H, room.compactTitle + 2 + room.sub + 2 * M.COMPACT_PAD)
  local blockY = math.floor((h - room.compactTitle - 2 - room.sub) / 2)
  for i, id in ipairs(ORDER) do
    local t, plan = f.compact[id], plans[id]
    local button = t.button
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (w + M.GAP), 0)
    button:SetSize(w, h)
    button:Show()
    paintIcons(t.icons, plan, M.COMPACT_PAD, math.floor((h - M.COMPACT_ICON) / 2), M.COMPACT_ICON, button)
    setText(t.title, titleOf(id))
    t.title:ClearAllPoints()
    t.title:SetPoint("TOPLEFT", button, "TOPLEFT", textX, -blockY)
    local subY = blockY + room.compactTitle + 2
    setText(t.sub, subOf(id, plan))
    t.sub:ClearAllPoints()
    t.sub:SetPoint("TOPLEFT", button, "TOPLEFT", textX, -subY)
    local own = paintTileButton(t, plan, ctx, true)
    t.sub:SetShown(not own)
    if own then
      setText(t.cast.count, HF.List.CountText(ctx.run))
      t.cast.count:ClearAllPoints()
      t.cast.count:SetPoint("TOPLEFT", button, "TOPLEFT", textX, -subY)
      t.cast.count:Show()
      HF.List.PaintFill(t.cast, button, textX, subY + countH + 2, textW, ctx.run)
    else
      HF.List.HideCast(t.cast)
    end
  end
  return h
end

-- The tiles with a followed group, full or compact as the search row shows or not; nothing without
-- one. Answers their height.
local function paint(f, ctx)
  if not ctx.hasGroups then return 0 end
  local mode = ctx.many and "compact" or "full"
  local plans, crafts = plansFor(ctx)
  local w = math.floor((ctx.width - 2 * M.GAP) / 3)
  for _, id in ipairs(ORDER) do
    f.full[id].card:SetShown(mode == "full")
    f.compact[id].button:SetShown(mode == "compact")
  end
  local h = mode == "full" and paintFull(f, plans, crafts, ctx, w) or paintCompact(f, plans, ctx, w)
  -- The other look's words shown for the first time: redrawn whole (docs/addon/AGENTS.md "Text").
  if f.mode ~= nil and f.mode ~= mode then U.restamp(HF._frame) end
  f.mode = mode
  return h
end

HF.AddSection("tiles", { build = build, paint = paint })
