local _, GC = ...

-- Retail's profession window: a GoldCap panel beside it, on the recipes page, as the owner approved
-- it (canvas version 17, 2026-10-26). Top to bottom:
-- - the header: the GoldCap mark and brand, and a chip with the open profession's icon and name;
-- - This recipe: the recipe the window shows, the icon of what it makes with its crafting quality,
--   how the queue holds it (crafts to make, or the target a restock keeps), and three figures:
--   what the reagents the player picked cost (a slot with nothing allocated at its cheapest priced
--   quality), what one craft sells for after the auction house cut, and the profit. A reagent or a
--   crafted item with no GoldCap price is named instead, as the strip names it (UI/CraftStrip.lua).
--   Add to queue and Restock to under them;
-- - the tabs: Worth crafting, and the Queue (UI/CraftQueueView.lua) with how many lines it has;
-- - Worth crafting: the recipes this character knows in the open profession that make a profit, by
--   profit per craft, each reagent at its cheapest priced quality. A row: the icon of what the
--   recipe makes, the craft's math, the profit, how many of its item sell a day where that is
--   known (or that it sells under once a day), and a "+" that puts one craft in the queue at once.
--   The row of the recipe the window shows is gold. A click on a row opens its recipe in the
--   window, a right click offers the queue. A recipe that makes no profit, and one GoldCap cannot
--   price (a reagent or what it makes has no price), are each counted under the list, never listed;
-- - the foot: where the prices come from and how old they are, as the Disenchant window says it.
-- Item icons, the brand, the tabs' track and the price line are the GoldCap Hoard's (UI/HoardRow.lua's
-- icon, UI/HoardFooter.lua's price line, UI/HoardFrame.lua's helpers), loaded before this file.
--
-- The panel is a frame of its own, a child of the crafting page so it goes with the page, and it
-- leaves Blizzard's frames as they are: no hook, no method replaced. It shows only for the
-- character's own recipes, never a guild's, a linked list or an NPC's. Its events are its own
-- (Core/Collection.lua's shape: each registered under pcall), so Core/Init.lua is not touched.
-- Every line it draws is drawn again whenever it shows again (docs/addon/AGENTS.md "Text").
GC.CraftPanel = GC.CraftPanel or {}
local P = GC.CraftPanel
local HF = GC.HoardFrame
local U = HF.ui
local K = GC.Kit.Tokens.color
local setText, colour, wrapping, heightOf, track, restamp = U.setText, U.colour, U.wrapping, U.heightOf, U.track,
  U.restamp

-- In UI units; the approved board is drawn at twice that (640 wide). PAD: the panel's margin, GAP
-- between its blocks, LINE_GAP between the lines of one. HEAD_H, LOGO, BRAND, BRAND_GAP: the
-- header, the GoldCap mark, the brand's size and the room between them. CHIP_H, CHIP_ICON,
-- CHIP_PAD: a chip, the profession's icon in it and the room either side of a chip's words.
-- CARD_PAD: This recipe's margin, ICON its item, ICON_GAP right of the item, BLOCK_GAP between its
-- parts; CELL_GAP, CELL_PAD, CELL_PAD_Y: its three figures; BUTTON_H, BUTTON_GAP, BUTTON_PAD,
-- GLYPH, GLYPH_GAP: its two buttons and their glyphs. SEG_H, SEG_PAD: a tab and the track round the
-- two; BADGE_H, BADGE_PAD, BADGE_GAP: the Queue's count after its word, the room either side of its
-- figures. A Worth crafting row: ROW_PAD and ROW_PAD_Y its margins, ROW_GAP between rows, ROW_ICON
-- its item, COL_GAP between its columns, ADD and ADD_ICON the "+", PACE_H the pace chip, NAME_MIN
-- the least room its name gets; BAR: the scroll's bar right of the list. The rest are font sizes.
local LAYOUT = {
  WIDTH = 320, PAD = 11, GAP = 8, LINE_GAP = 2,
  HEAD_H = 24, LOGO = 20, BRAND = 15, BRAND_GAP = 6, CHIP_H = 18, CHIP_ICON = 13, CHIP_PAD = 6,
  CARD_PAD = 8, ICON = 28, ICON_GAP = 7, BLOCK_GAP = 7, CELL_GAP = 4, CELL_PAD = 6, CELL_PAD_Y = 5,
  BUTTON_H = 22, BUTTON_GAP = 5, BUTTON_PAD = 8, GLYPH = 10, GLYPH_GAP = 5,
  SEG_H = 21, SEG_PAD = 2, BADGE_H = 13, BADGE_PAD = 4, BADGE_GAP = 5,
  ROW_PAD = 6, ROW_PAD_Y = 5, ROW_GAP = 3, ROW_ICON = 24, COL_GAP = 6, ADD = 18, ADD_ICON = 9, PACE_H = 14,
  NAME_MIN = 80, BAR = 16,
  KICKER = 9, NAME = 12, LABEL = 9, FIGURE = 11, ROW_NAME = 11, SMALL = 9, NOTE = 10,
}
LAYOUT.INNER = LAYOUT.WIDTH - 2 * LAYOUT.PAD
LAYOUT.ROW_W = LAYOUT.INNER - LAYOUT.BAR
-- The width a view in the panel's body draws in (UI/CraftQueueView.lua).
P.BODY_W = LAYOUT.INNER

local function tint(c, a) return { c[1], c[2], c[3], a } end
-- The board's colours, from the kit's tokens: This recipe on a faint gold wash in a gold ring; a
-- figure on the window's dark, the profit on a wash and a ring of its own colour; a Worth crafting
-- row on the glass in a hairline, the open recipe's on This recipe's gold; Restock to and the "+"
-- ringed in gold.
local CARD_FILL, CARD_RING = tint(K.gold, 0.07), tint(K.gold, 0.5)
local CELL_FILL, NO_RING = { 0, 0, 0, 0.3 }, { 0, 0, 0, 0 }
local OPEN_FILL, OPEN_RING = tint(K.gold, 0.07), tint(K.gold, 0.45)
local GOLD_RING = tint(K.gold, 0.5)

-- What changes the list: the window opening, its recipe list refreshed, a recipe learned. Bags
-- changing moves nothing here, but the queue reads them (UI/CraftQueueView.lua): a bag change
-- repaints that view alone, never the whole list, which fires on every craft of a Create All.
local EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED", "BAG_UPDATE_DELAYED" }

-- What changes This recipe's figures and nothing else: another reagent picked, the transaction
-- rebuilt (Blizzard_ProfessionsTransaction.lua). Each asks for one repaint of This recipe on the
-- next frame; the Worth crafting list prices every recipe at its cheapest reagents, whatever the
-- form holds.
local OPEN_CALLBACKS = { "Professions.AllocationUpdated", "Professions.TransactionUpdated" }

local function window()
  local frame = _G.ProfessionsFrame
  return type(frame) == "table" and frame or nil
end

local function after(fn)
  local timer = _G.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, fn) else fn() end
end

local function textWidth(fs)
  return math.ceil(fs:GetUnboundedStringWidth() or 0)
end

-- Lays `parts` ({ region, width }) out left to right in button `b`, `gap` apart and centred together
-- in it: a glyph and the words (Add to queue, Restock to), the words and a count (the Queue tab).
-- The words keep their own width, anchored by their left edge alone: so after SetLabel, which
-- bounds them by the button's edges again.
local function centreIn(b, parts, gap)
  local total = gap * (#parts - 1)
  for _, part in ipairs(parts) do total = total + part[2] end
  local x = math.floor((b:GetWidth() - total) / 2)
  for _, part in ipairs(parts) do
    part[1]:ClearAllPoints()
    part[1]:SetPoint("LEFT", b, "LEFT", x, 0)
    x = x + part[2] + gap
  end
end

-- A chip as wide as its words with CHIP_PAD either side: a chip's words are never cut.
local function fitChip(chip, text, color)
  chip:SetLabel(text, color)
  chip:SetWidth(textWidth(chip.text) + 2 * LAYOUT.CHIP_PAD)
end

-- ---------------------------------------------------------------------------------------------
-- Putting recipes in the queue: This recipe's buttons, a row's "+" and right click
-- ---------------------------------------------------------------------------------------------

local function queueChanged()
  if P.OnQueueChanged then P.OnQueueChanged() end
  P.Queue()
end

-- `n` crafts of `recipe` into `char`'s queue, then the list and the panel as the queue now stands.
local function addCrafts(char, recipe, n)
  GC.CraftQueue.Add(char, recipe, n)
  queueChanged()
end

local function entryOf(char, recipeID)
  for _, e in ipairs(GC.CraftQueue.Entries(char)) do
    if e.recipe.recipeID == recipeID then return e end
  end
  return nil
end

--- Asks how many crafts of `recipe` to add to this character's queue (BUY's popup), and adds them.
function P.AskCount(anchor, recipe)
  local char = GC.CraftClient.Char()
  if not (char and type(recipe) == "table") then return end
  GC.BuyCapEditor.Open(anchor, {
    title = GC.L["How many crafts of %s?"]:format(recipe.name),
    text = "1",
    read = function(text) return GC.CraftQueue.ParseCount(text) end,
    invalid = GC.L["Type a whole number"],
    setLabel = GC.L["Add"],
    onCommit = function(n) addCrafts(char, recipe, n) end,
  })
end

--- Worth crafting's "+": one craft of `recipe` into this character's queue at once, no question.
function P.AddOne(recipe)
  local char = GC.CraftClient.Char()
  if char and type(recipe) == "table" then addCrafts(char, recipe, 1) end
end

--- Asks how many of what `recipe` makes to keep on hand; 0 takes the recipe off the queue.
function P.AskRestock(anchor, recipe)
  local char = GC.CraftClient.Char()
  if not (char and type(recipe) == "table") then return end
  local entry = entryOf(char, recipe.recipeID)
  GC.BuyCapEditor.Open(anchor, {
    title = GC.L["Restock %s to how many? 0 takes it off the queue."]:format(recipe.name),
    text = entry and entry.restock and tostring(entry.restock) or "",
    read = function(text) return GC.CraftQueue.ParseCount(text, true) end,
    invalid = GC.L["Type a whole number"],
    setLabel = GC.L["Save"],
    onCommit = function(n)
      GC.CraftQueue.Restock(char, recipe, n)
      queueChanged()
    end,
  })
end

--- A Worth crafting row's right click: queue its recipe with a count, or restock it.
function P.OpenRowMenu(owner, recipe)
  local menu = _G.MenuUtil
  if not (type(menu) == "table" and menu.CreateContextMenu and type(recipe) == "table" and GC.CraftQueue.Writable()) then
    return false
  end
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(GC.Util.ClientText(recipe.name))
    root:CreateButton(GC.Util.ClientText(GC.L["Add to queue"]), function() P.AskCount(owner, recipe) end)
    root:CreateButton(GC.Util.ClientText(GC.L["Restock to"]), function() P.AskRestock(owner, recipe) end)
  end)
  return true
end

-- How `char`'s queue holds `recipeID`, or nil when it does not: the crafts a count has left to make,
-- or the target a restock keeps. How far along a restock is, the Queue's line says
-- (UI/CraftQueueView.lua), the one place that counts what is held.
local function queuedText(char, recipeID)
  local e = entryOf(char, recipeID)
  if not e then return nil end
  if e.restock then return GC.L["Restock to %d"]:format(e.restock) end
  return GC.L["In queue: %d"]:format(GC.CraftQueue.CraftsNeeded(e))
end

-- ---------------------------------------------------------------------------------------------
-- Worth crafting
-- ---------------------------------------------------------------------------------------------

local function buildWorth(body)
  local T = GC.Theme
  local v = CreateFrame("Frame", nil, body)
  v:SetAllPoints(body)
  v.heading = track(v, wrapping(T.Heading(v, LAYOUT.KICKER)))
  colour(v.heading, K.text3)
  v.cheapest = track(v, wrapping(T.Label(v, LAYOUT.SMALL)))
  colour(v.cheapest, K.text4)
  v.empty = track(v, wrapping(T.Label(v, LAYOUT.NOTE)))
  v.empty:SetWidth(LAYOUT.INNER)
  colour(v.empty, K.text2)
  v.unprofitable = track(v, wrapping(T.Label(v, LAYOUT.NOTE)))
  v.unpriced = track(v, wrapping(T.Label(v, LAYOUT.NOTE)))
  for _, fs in ipairs({ v.unprofitable, v.unpriced }) do
    fs:SetWidth(LAYOUT.INNER)
    colour(fs, K.text3)
  end
  v.scroll = CreateFrame("ScrollFrame", nil, v, "UIPanelScrollFrameTemplate")
  T.QuietScrollBar(v.scroll)
  v.content = CreateFrame("Frame", nil, v.scroll)
  v.content:SetSize(LAYOUT.ROW_W, 1)
  v.scroll:SetScrollChild(v.content)
  v.rows = {}
  return v
end

-- Worth crafting shown again (the panel's page, or its tab): its lines and every row it shows drawn
-- again.
local function restampWorth(v)
  restamp(v)
  for _, row in ipairs(v.rows) do
    if row.frame:IsShown() then restamp(row) end
  end
end

-- The "+"'s tooltip: what a press does.
local function addTip(button)
  local tip = _G.GameTooltip
  if not tip then return end
  tip:SetOwner(button, "ANCHOR_RIGHT")
  tip:SetText(GC.Util.ClientText(GC.L["Add one craft to the queue"]), 1, 1, 1, 1, true)
  tip:Show()
end

-- A row on the glass in a hairline, with the engine's gold wash under the cursor (HF.ui.plate):
-- what the recipe makes, its name over the craft's math, the profit over the pace chip, the "+".
local function newRow(v)
  local T = GC.Theme
  local frame = U.plate(v.content, K.hairline, "plaque")
  frame:SetWidth(LAYOUT.ROW_W)
  frame.fill = T.SlicedTexture(frame, "BACKGROUND", T.MEDIA .. "plaque.png", K.glassTop, T.SLICE.plaque)
  frame.fill:SetAllPoints()
  local row = { frame = frame }
  row.slot = HF.Row.NewIcon(frame, LAYOUT.ROW_ICON)
  row.slot.edge:SetPoint("LEFT", frame, "LEFT", LAYOUT.ROW_PAD, 0)
  row.name = track(row, wrapping(T.Label(frame, LAYOUT.ROW_NAME)))
  colour(row.name, K.text1)
  row.math = track(row, wrapping(T.Label(frame, LAYOUT.SMALL)))
  colour(row.math, K.text3)
  -- The profit is one line and never cut: a FontString with no width of its own is as wide as its
  -- text (coins included), and the name wraps in what is left beside it.
  row.profit = track(row, T.Num(frame, LAYOUT.FIGURE, true))
  row.profit:SetWordWrap(false)
  row.pace = T.Chip(frame)
  row.pace:SetHeight(LAYOUT.PACE_H)
  track(row, row.pace.text)
  row.add = T.Button(frame, "active", "badge")
  row.add:SetSize(LAYOUT.ADD, LAYOUT.ADD)
  row.add:SetRing(GOLD_RING)
  row.add:SetPoint("RIGHT", frame, "RIGHT", -LAYOUT.ROW_PAD, 0)
  row.add.glyph = row.add:CreateTexture(nil, "OVERLAY")
  row.add.glyph:SetSize(LAYOUT.ADD_ICON, LAYOUT.ADD_ICON)
  row.add.glyph:SetPoint("CENTER", row.add, "CENTER", 0, 0)
  T.SetIcon(row.add.glyph, "plus", K.goldText)
  row.add:SetScript("OnClick", function() if row.data then P.AddOne(row.data.recipe) end end)
  row.add:SetScript("OnEnter", addTip)
  row.add:SetScript("OnLeave", U.hideTip)
  -- A click opens the row's recipe in Blizzard's window, called from the click itself as Blizzard's
  -- recipe tracker does (CraftClient.Open); a right click offers to queue it (UI/BuyLists.lua's
  -- menu, in the client's font).
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame:SetScript("OnClick", function(self, button)
    local data = row.data
    if not data then return end
    if button == "RightButton" then
      P.OpenRowMenu(self, data.recipe)
    else
      GC.CraftClient.Open(data.recipeID)
    end
  end)
  return row
end

-- "Costs 212g, sells for 354g", or "5 a craft. Costs 437g, sells for 475g" for a recipe that makes
-- more than one: what one craft costs and sells for, all it makes.
local function mathLine(recipe, result)
  local cost, sells = GC.Util.Money(result.cost), GC.Util.Money(result.sells)
  if (recipe.per or 1) > 1 then return GC.L["%d a craft. Costs %s, sells for %s"]:format(recipe.per, cost, sells) end
  return GC.L["Costs %s, sells for %s"]:format(cost, sells)
end

-- How fast the item sells, and in what colour: how many a day in green, under one a day amber,
-- nothing where that is not known.
local function paceOf(sold)
  if GC.CraftMath.IsSlow(sold) then return GC.L["Slow seller"], K.warn end
  if type(sold) == "number" then return GC.L["about %s a day"]:format(GC.Util.Grouped(sold)), K.profit end
  return nil
end

-- One row, its parts centred down it: the icon at the left, the "+" at the right, left of it the
-- profit over the pace chip, both as wide as their text, and the name and the math wrapped in what
-- is left. When that would leave the name less than NAME_MIN (a wide profit or pace, a large font),
-- the profit and the pace go under the math instead, and the name and the math take the whole
-- width, so nothing runs under the column. `ctx`: the recipe the window shows (`open`) and whether
-- the "+" can queue (`canAdd`). Answers the row's height, as tall as its wrapped text.
local function paintRow(row, data, ctx)
  local frame, recipe = row.frame, data.recipe
  local isOpen = data.recipeID == ctx.open
  local fill, ring = isOpen and OPEN_FILL or K.glassTop, isOpen and OPEN_RING or K.hairline
  frame.fill:SetVertexColor(fill[1], fill[2], fill[3], fill[4])
  frame.ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4])
  HF.Row.PaintIcon(row.slot, recipe.output, GC.CraftClient.IconOf(recipe.output), nil, nil, { pip = true })
  setText(row.name, data.name)
  setText(row.math, mathLine(recipe, data.result))
  setText(row.profit, "+" .. GC.Util.Money(data.result.profit))
  colour(row.profit, K.profit)
  local pace, tone = paceOf(data.sold)
  if pace then fitChip(row.pace, pace, tone) end
  row.pace:SetShown(pace ~= nil)
  row.add:SetShown(ctx.canAdd)

  local right = LAYOUT.ROW_W - LAYOUT.ROW_PAD - (ctx.canAdd and (LAYOUT.ADD + LAYOUT.COL_GAP) or 0)
  local colW = math.max(textWidth(row.profit), pace and row.pace:GetWidth() or 0)
  local left = LAYOUT.ROW_PAD + LAYOUT.ROW_ICON + LAYOUT.COL_GAP
  local beside = right - colW - LAYOUT.COL_GAP - left >= LAYOUT.NAME_MIN
  local width = beside and (right - colW - LAYOUT.COL_GAP - left) or (right - left)
  row.name:SetWidth(width)
  row.math:SetWidth(width)
  local colH = heightOf(row.profit, 13) + (pace and (LAYOUT.LINE_GAP + LAYOUT.PACE_H) or 0)
  local textH = heightOf(row.name, 14) + LAYOUT.LINE_GAP + heightOf(row.math, 12)
  if not beside then textH = textH + LAYOUT.LINE_GAP + colH end
  local inside = math.max(LAYOUT.ROW_ICON, LAYOUT.ADD, textH, beside and colH or 0)
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -(LAYOUT.ROW_PAD_Y + math.floor((inside - textH) / 2)))
  row.math:ClearAllPoints()
  row.math:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  row.profit:ClearAllPoints()
  row.pace:ClearAllPoints()
  if beside then
    row.profit:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right - LAYOUT.ROW_W,
      -(LAYOUT.ROW_PAD_Y + math.floor((inside - colH) / 2)))
    row.pace:SetPoint("TOPRIGHT", row.profit, "BOTTOMRIGHT", 0, -LAYOUT.LINE_GAP)
  else
    row.profit:SetPoint("TOPLEFT", row.math, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
    row.pace:SetPoint("TOPLEFT", row.profit, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  end
  local height = inside + 2 * LAYOUT.ROW_PAD_Y
  frame:SetHeight(height)
  row.data = data
  frame:Show()
  return height
end

-- The line over the list: its heading at the left and "reagents at their cheapest quality" at the
-- right, or under it when the two do not fit side by side. Answers its height.
local function paintHeading(v)
  setText(v.heading, GC.Util.Upper(GC.L["Best profit a craft"]))
  setText(v.cheapest, GC.L["reagents at their cheapest quality"])
  local a, b = textWidth(v.heading) + 1, textWidth(v.cheapest) + 1
  v.heading:ClearAllPoints()
  v.heading:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
  v.cheapest:ClearAllPoints()
  if a + LAYOUT.GAP + b <= LAYOUT.INNER then
    v.heading:SetWidth(a)
    v.cheapest:SetWidth(b)
    v.cheapest:SetJustifyH("RIGHT")
    v.cheapest:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, 0)
    return math.max(heightOf(v.heading, 11), heightOf(v.cheapest, 11))
  end
  v.heading:SetWidth(LAYOUT.INNER)
  v.cheapest:SetWidth(LAYOUT.INNER)
  v.cheapest:SetJustifyH("LEFT")
  v.cheapest:SetPoint("TOPLEFT", v.heading, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  return heightOf(v.heading, 11) + LAYOUT.LINE_GAP + heightOf(v.cheapest, 11)
end

--- Worth crafting's rows: every known recipe that makes a profit, by profit per craft, then how
--- many GoldCap could not price and how many it priced that make no profit.
function P.Rows()
  local CC = GC.CraftClient
  local rows = {}
  for _, id in ipairs(CC.KnownRecipes()) do
    local recipe = CC.Snapshot(id)
    if recipe then
      local _, sold = CC.SellOf(recipe.output)
      rows[#rows + 1] = { recipeID = id, name = recipe.name, recipe = recipe, result = CC.ProfitOf(recipe), sold = sold }
    end
  end
  return GC.CraftMath.Rank(rows)
end

function P.PaintWorth()
  local CC = GC.CraftClient
  local v = P._frame.worth
  local headH = paintHeading(v)
  local ranked, unpriced, unprofitable = P.Rows()
  P._rows = ranked
  local open = CC.OpenRecipe()
  local ctx = { open = open and open.recipeID, canAdd = CC.Char() ~= nil and GC.CraftQueue.Writable() }
  local total = 0
  for i, data in ipairs(ranked) do
    local row = v.rows[i] or newRow(v)
    v.rows[i] = row
    local wasUp = row.frame:IsShown()
    local height = paintRow(row, data, ctx)
    -- A pooled row a shorter list hid, shown again: drawn again whole.
    if not wasUp and v:IsShown() then restamp(row) end
    row.frame:ClearAllPoints()
    if i == 1 then
      row.frame:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, 0)
    else
      row.frame:SetPoint("TOPLEFT", v.rows[i - 1].frame, "BOTTOMLEFT", 0, -LAYOUT.ROW_GAP)
      total = total + LAYOUT.ROW_GAP
    end
    data.widget = row
    total = total + height
  end
  for i = #ranked + 1, #v.rows do
    v.rows[i].frame:Hide()
    v.rows[i].data = nil
  end
  v.content:SetHeight(math.max(1, total))

  if #ranked == 0 then
    setText(v.empty, unprofitable > 0 and GC.L["No recipe here makes a profit now"]
      or GC.L["No recipe here has a GoldCap price yet"])
    v.empty:ClearAllPoints()
    v.empty:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -(headH + LAYOUT.GAP))
    v.empty:Show()
    v.scroll:Hide()
  else
    v.empty:Hide()
    v.scroll:Show()
  end
  -- At the view's foot: how many make no profit (not under an empty list, whose own line says it
  -- already), over how many have no price, each as tall as its wrapped text.
  local foot, below = 0, nil
  if unpriced > 0 then
    setText(v.unpriced, unpriced == 1 and GC.L["1 has no GoldCap price for a reagent or what it makes."]
      or GC.L["%d have no GoldCap price for a reagent or what they make."]:format(unpriced))
    v.unpriced:ClearAllPoints()
    v.unpriced:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 0, 0)
    v.unpriced:Show()
    foot, below = heightOf(v.unpriced, 12), v.unpriced
  else
    v.unpriced:Hide()
  end
  if unprofitable > 0 and #ranked > 0 then
    setText(v.unprofitable, unprofitable == 1 and GC.L["1 more recipe makes no profit now."]
      or GC.L["%d more recipes make no profit now."]:format(unprofitable))
    v.unprofitable:ClearAllPoints()
    if below then
      v.unprofitable:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, LAYOUT.LINE_GAP)
      foot = foot + LAYOUT.LINE_GAP
    else
      v.unprofitable:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 0, 0)
    end
    v.unprofitable:Show()
    foot = foot + heightOf(v.unprofitable, 12)
  else
    v.unprofitable:Hide()
  end
  -- The list takes what the heading and the foot leave, and scrolls in it.
  v.scroll:ClearAllPoints()
  v.scroll:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -(headH + LAYOUT.GAP))
  v.scroll:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -LAYOUT.BAR, foot > 0 and (foot + LAYOUT.GAP) or 0)
end

-- ---------------------------------------------------------------------------------------------
-- This recipe
-- ---------------------------------------------------------------------------------------------

-- A button with the kit's glyph before its words, `color` the variant's lettering.
local function glyphButton(parent, variant, glyph, color)
  local b = GC.Theme.Button(parent, variant, "badge")
  b:SetHeight(LAYOUT.BUTTON_H)
  b:SetGlow(false)
  b.text:SetJustifyH("LEFT")
  b.glyph = b:CreateTexture(nil, "OVERLAY")
  b.glyph:SetSize(LAYOUT.GLYPH, LAYOUT.GLYPH)
  GC.Theme.SetIcon(b.glyph, glyph, color)
  return b
end

local function buildCard(f)
  local T = GC.Theme
  local card = T.Card(f, CARD_FILL, CARD_RING)
  card:SetWidth(LAYOUT.INNER)
  card.slot = HF.Row.NewIcon(card, LAYOUT.ICON)
  card.kicker = track(f, wrapping(T.Heading(card, LAYOUT.KICKER)))
  colour(card.kicker, K.text3)
  card.name = track(f, wrapping(T.Label(card, LAYOUT.NAME)))
  colour(card.name, K.text1)
  card.queued = T.Chip(card)
  card.queued:SetHeight(LAYOUT.CHIP_H)
  track(f, card.queued.text)
  -- Reagents, Sells for after cut, Profit a craft: each label wrapped in its cell, the figure on one
  -- line along the cell's foot, so the three figures stand level whatever their labels need.
  card.cells = {}
  for i = 1, 3 do
    local cell = T.Card(card, CELL_FILL, NO_RING, true)
    cell.label = track(f, wrapping(T.Label(cell, LAYOUT.LABEL)))
    cell.label:SetPoint("TOPLEFT", cell, "TOPLEFT", LAYOUT.CELL_PAD, -LAYOUT.CELL_PAD_Y)
    colour(cell.label, K.text3)
    cell.value = track(f, T.Num(cell, LAYOUT.FIGURE, true))
    cell.value:SetJustifyH("LEFT")
    cell.value:SetWordWrap(false)
    cell.value:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", LAYOUT.CELL_PAD, LAYOUT.CELL_PAD_Y)
    card.cells[i] = cell
  end
  card.missing = track(f, wrapping(T.Label(card, LAYOUT.NOTE)))
  colour(card.missing, K.text1)
  card.add = glyphButton(card, "primary", "plus", K.onGold)
  card.add:SetScript("OnClick", function(self) if card.recipe then P.AskCount(self, card.recipe) end end)
  card.restock = glyphButton(card, "active", "refresh", K.goldText)
  card.restock:SetRing(GOLD_RING)
  card.restock:SetScript("OnClick", function(self) if card.recipe then P.AskRestock(self, card.recipe) end end)
  track(f, card.add.text)
  track(f, card.restock.text)
  card:Hide()
  return card
end

-- The three figures side by side from `y` down the card, `inner` wide. The profit in green on a
-- green wash and ring, a loss in the kit's red with no plus sign. Answers their height.
local function paintCells(card, result, inner, y)
  local profit = result.profit
  local tone = profit > 0 and K.profit or (profit < 0 and K.loss or nil)
  local figures = {
    { GC.L["Reagents"], GC.Util.Money(result.cost) },
    { GC.L["Sells for, after cut"], GC.Util.Money(result.sells) },
    { GC.L["Profit a craft"], (profit > 0 and "+" or "") .. GC.Util.Money(profit) },
  }
  local w = math.floor((inner - 2 * LAYOUT.CELL_GAP) / 3)
  local labelH, valueH = 0, 0
  for i, cell in ipairs(card.cells) do
    cell.label:SetWidth(w - 2 * LAYOUT.CELL_PAD)
    setText(cell.label, figures[i][1])
    setText(cell.value, figures[i][2])
    colour(cell.value, i == 3 and tone or K.text1)
    labelH = math.max(labelH, heightOf(cell.label, 11))
    valueH = math.max(valueH, heightOf(cell.value, 13))
  end
  local height = 2 * LAYOUT.CELL_PAD_Y + labelH + LAYOUT.LINE_GAP + valueH
  for i, cell in ipairs(card.cells) do
    cell:SetSize(w, height)
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.CARD_PAD + (i - 1) * (w + LAYOUT.CELL_GAP), -y)
    cell:Show()
  end
  card.cells[3]:SetTint(tone and tint(tone, 0.08) or CELL_FILL, tone and tint(tone, 0.3) or NO_RING)
  return height
end

-- How wide a glyph button needs to be for its glyph and its words, with its margins.
local function glyphWidth(b)
  return 2 * LAYOUT.BUTTON_PAD + LAYOUT.GLYPH + LAYOUT.GLYPH_GAP + textWidth(b.text)
end

-- A glyph button `width` wide, its glyph and its words centred together in it. After SetLabel.
local function fitGlyph(b, width)
  b:SetWidth(width)
  centreIn(b, { { b.glyph, LAYOUT.GLYPH }, { b.text, textWidth(b.text) } }, LAYOUT.GLYPH_GAP)
end

-- What the Queue view (UI/CraftQueueView.lua) draws as this panel does: how wide a line of text is,
-- and Make a BUY list, a glyph button as Add to queue is.
P.ui = { textWidth = textWidth, glyphButton = glyphButton, fitGlyph = fitGlyph }

-- Add to queue and Restock to from `y` down the card, `inner` wide, as wide as each other: side by
-- side when the wider fits half the card in the player's language, else one under the other across
-- it. Answers their height.
local function paintButtons(card, inner, y)
  local add, restock = card.add, card.restock
  add:SetLabel(GC.L["Add to queue"])
  restock:SetLabel(GC.L["Restock to"])
  local half = math.floor((inner - LAYOUT.BUTTON_GAP) / 2)
  local beside = math.max(glyphWidth(add), glyphWidth(restock)) <= half
  add:ClearAllPoints()
  add:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.CARD_PAD, -y)
  restock:ClearAllPoints()
  if beside then
    restock:SetPoint("LEFT", add, "RIGHT", LAYOUT.BUTTON_GAP, 0)
  else
    restock:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -LAYOUT.BUTTON_GAP)
  end
  for _, b in ipairs({ add, restock }) do
    fitGlyph(b, beside and half or inner)
    b:Show()
  end
  return beside and LAYOUT.BUTTON_H or (2 * LAYOUT.BUTTON_H + LAYOUT.BUTTON_GAP)
end

-- The card for the recipe the window shows, hidden for one GoldCap does not price (salvage, a
-- recraft, an enchant). Its figures are the window's own allocation's (CraftClient.ProfitOf), and
-- they show whatever else holds: Add to queue and Restock to only when the recipe can be queued,
-- never for a recipe the character has not learned (Blizzard's list shows those too: one could
-- never be crafted from the queue), nor without a character or with a store a newer GoldCap wrote.
local function paintCard(f)
  local card = f.card
  local CC = GC.CraftClient
  local open = CC.OpenRecipe()
  local recipe = open and CC.Snapshot(open.recipeID) or nil
  local char = CC.Char()
  local queueable = recipe ~= nil and open.learned == true and char ~= nil and GC.CraftQueue.Writable()
  card.recipe = queueable and recipe or nil
  if not recipe then
    card:Hide()
    return
  end
  local inner = LAYOUT.INNER - 2 * LAYOUT.CARD_PAD
  -- What this allocation makes, as the window says, else what the recipe makes. The window's
  -- item comes with its link, which says crafted gear's quality (Theme.QualityAtlas).
  local item = open.output or recipe.output
  HF.Row.PaintIcon(card.slot, item, CC.IconOf(item), nil, nil, { pip = true, link = open.output and open.link or nil })
  setText(card.kicker, GC.Util.Upper(GC.L["This recipe"]))
  setText(card.name, recipe.name)
  local queued = char and queuedText(char, recipe.recipeID) or nil
  if queued then fitChip(card.queued, queued, K.yours) end
  card.queued:SetShown(queued ~= nil)
  -- The top line: the item, the kicker over the name (wrapped in what the item and the chip leave),
  -- the chip at the right, each centred on the line.
  local textX = LAYOUT.CARD_PAD + LAYOUT.ICON + LAYOUT.ICON_GAP
  local textW = inner - LAYOUT.ICON - LAYOUT.ICON_GAP - (queued and (card.queued:GetWidth() + LAYOUT.ICON_GAP) or 0)
  card.kicker:SetWidth(textW)
  card.name:SetWidth(textW)
  local textH = heightOf(card.kicker, 11) + LAYOUT.LINE_GAP + heightOf(card.name, 14)
  local lineH = math.max(LAYOUT.ICON, textH, queued and LAYOUT.CHIP_H or 0)
  local y = LAYOUT.CARD_PAD
  card.slot.edge:ClearAllPoints()
  card.slot.edge:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.CARD_PAD, -(y + math.floor((lineH - LAYOUT.ICON) / 2)))
  card.kicker:ClearAllPoints()
  card.kicker:SetPoint("TOPLEFT", card, "TOPLEFT", textX, -(y + math.floor((lineH - textH) / 2)))
  card.name:ClearAllPoints()
  card.name:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  card.queued:ClearAllPoints()
  card.queued:SetPoint("TOPRIGHT", card, "TOPRIGHT", -LAYOUT.CARD_PAD, -(y + math.floor((lineH - LAYOUT.CHIP_H) / 2)))
  y = y + lineH + LAYOUT.BLOCK_GAP

  local result = CC.ProfitOf(recipe, open)
  if result.missing then
    for _, cell in ipairs(card.cells) do cell:Hide() end
    card.missing:SetWidth(inner)
    setText(card.missing, GC.CraftStrip.Lines(result)[1].text)
    card.missing:ClearAllPoints()
    card.missing:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.CARD_PAD, -y)
    card.missing:Show()
    y = y + heightOf(card.missing, 14)
  else
    card.missing:Hide()
    y = y + paintCells(card, result, inner, y)
  end
  if queueable then
    y = y + LAYOUT.BLOCK_GAP
    y = y + paintButtons(card, inner, y)
  else
    card.add:Hide()
    card.restock:Hide()
  end
  card:SetHeight(y + LAYOUT.CARD_PAD)
  card:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The tabs: Worth crafting or the Queue (UI/CraftQueueView.lua), for this session
-- ---------------------------------------------------------------------------------------------

--- The view the body shows: "queue" once the player picked it and the Queue view is there.
function P.View()
  local qv = GC.CraftQueueView
  if P._view == "queue" and qv and qv._frame then return "queue" end
  return "worth"
end

-- A segmented control in the sunken track the Hoard's switches have (HF.ui.sunkenTrack): the view
-- on screen filled gold, the other bare words; the Queue with a round count of its lines after its
-- word.
local function buildSwitch(f)
  local T = GC.Theme
  local sw = CreateFrame("Frame", nil, f)
  U.sunkenTrack(sw)
  for _, id in ipairs({ "worth", "queue" }) do
    local b = T.Button(sw, "segment", "badge")
    b:SetGlow(false)
    b:SetHeight(LAYOUT.SEG_H)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function()
      P._view = id
      P.Refresh()
    end)
    sw[id] = b
    track(f, b.text)
  end
  sw.badge = T.Chip(sw.queue)
  sw.badge:SetHeight(LAYOUT.BADGE_H)
  -- The count centred on its own, as wide as its figures (the chip bounds its words 4px in from
  -- each side and cuts what does not fit); the badge is BADGE_PAD wider either side.
  sw.badge.text:ClearAllPoints()
  sw.badge.text:SetPoint("CENTER", sw.badge, "CENTER", 0, 0)
  track(f, sw.badge.text)
  return sw
end

-- The two halves of the panel's width side by side when both words (and the count) fit half in the
-- player's language, else one under the other across it.
local function paintSwitch(f)
  local sw = f.switch
  local view = P.View()
  local lines = #GC.CraftQueue.Entries(GC.CraftClient.Char())
  local badge = sw.badge
  sw.worth:SetLabel(GC.L["Worth crafting"])
  sw.queue:SetLabel(GC.L["Queue"])
  if lines > 0 then
    badge:SetLabel(tostring(lines), view == "queue" and K.onGold or K.goldText)
    badge:SetWidth(math.max(LAYOUT.BADGE_H, textWidth(badge.text) + 2 * LAYOUT.BADGE_PAD))
  end
  badge:SetShown(lines > 0)
  local parts = {
    worth = { { sw.worth.text, textWidth(sw.worth.text) } },
    queue = { { sw.queue.text, textWidth(sw.queue.text) } },
  }
  if lines > 0 then parts.queue[2] = { badge, badge:GetWidth() } end
  local need = 0
  for _, list in pairs(parts) do
    local w = 2 * LAYOUT.BUTTON_PAD + LAYOUT.BADGE_GAP * (#list - 1)
    for _, part in ipairs(list) do w = w + part[2] end
    need = math.max(need, w)
  end
  local pad = LAYOUT.SEG_PAD
  local half = math.floor((LAYOUT.INNER - 3 * pad) / 2)
  local beside = need <= half
  sw.worth:ClearAllPoints()
  sw.worth:SetPoint("TOPLEFT", sw, "TOPLEFT", pad, -pad)
  sw.queue:ClearAllPoints()
  if beside then
    sw.queue:SetPoint("LEFT", sw.worth, "RIGHT", pad, 0)
    sw:SetSize(LAYOUT.INNER, LAYOUT.SEG_H + 2 * pad)
  else
    sw.queue:SetPoint("TOPLEFT", sw.worth, "BOTTOMLEFT", 0, -pad)
    sw:SetSize(LAYOUT.INNER, 2 * LAYOUT.SEG_H + 3 * pad)
  end
  for _, id in ipairs({ "worth", "queue" }) do
    local b = sw[id]
    b:SetVariant(id == view and "primary" or "segment")
    b:SetWidth(beside and half or (LAYOUT.INNER - 2 * pad))
    centreIn(b, parts[id], LAYOUT.BADGE_GAP)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The header and the foot
-- ---------------------------------------------------------------------------------------------

-- The GoldCap mark and the brand as the Hoard's header draws them (HF.ui.newBrand), and the open
-- profession's chip at the right, its icon round as Blizzard's portraits are.
local function buildHeader(f)
  local T = GC.Theme
  local head = CreateFrame("Frame", nil, f)
  head:SetSize(LAYOUT.INNER, LAYOUT.HEAD_H)
  head:SetPoint("TOPLEFT", f, "TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  f.header = head
  U.newBrand(f, LAYOUT.LOGO, LAYOUT.BRAND, LAYOUT.BRAND_GAP)
  f.logo:SetPoint("LEFT", head, "LEFT", 0, 0)
  f.brand:SetText("GoldCap")
  local chip = T.Chip(head)
  chip:SetHeight(LAYOUT.CHIP_H)
  chip:SetPoint("RIGHT", head, "RIGHT", 0, 0)
  chip.icon = chip:CreateTexture(nil, "OVERLAY")
  chip.icon:SetSize(LAYOUT.CHIP_ICON, LAYOUT.CHIP_ICON)
  chip.icon:SetPoint("LEFT", chip, "LEFT", 3, 0)
  chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  chip.icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  track(f, chip.text)
  f.profession = chip
end

-- The profession chip: its icon, when the client has one, then its name; none when the client names
-- no profession.
local function paintHeader(f)
  local chip = f.profession
  local name, icon = GC.CraftClient.Profession()
  if not name then
    chip:Hide()
    return
  end
  chip:SetLabel(name, K.text2)
  if icon then chip.icon:SetTexture(icon) end
  chip.icon:SetShown(icon ~= nil)
  local x = icon and (3 + LAYOUT.CHIP_ICON + 4) or LAYOUT.CHIP_PAD
  chip.text:ClearAllPoints()
  chip.text:SetPoint("LEFT", chip, "LEFT", x, 0)
  chip:SetWidth(x + textWidth(chip.text) + LAYOUT.CHIP_PAD)
  chip:Show()
end

-- Where the prices come from and how old they are, beside a dot in the kit's green while they are
-- fresh, amber after or with none: the Hoard's price line (HF.Footer), as the Disenchant window's
-- foot draws it. Keeps its height for the layout.
local function paintFoot(f)
  f.footH = HF.Footer.PaintPriceLine(f, LAYOUT.PAD, LAYOUT.PAD, LAYOUT.INNER)
end

-- ---------------------------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------------------------

local function build(frame)
  local T = GC.Theme
  local f = CreateFrame("Frame", nil, frame.CraftingPage)
  f.glass = T.Window(f)
  f:SetWidth(LAYOUT.WIDTH)
  f:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
  -- The recipes page is 942 wide: on a 16:10 or 4:3 screen, or with the window pushed to the
  -- centre, the panel's right edge (the profit column) would fall off the screen. Clamped, the
  -- client slides it back over the window instead. Blizzard's own UI panel width is left alone.
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  buildHeader(f)
  f.card = buildCard(f)
  f.switch = buildSwitch(f)
  HF.Footer.NewPriceLine(f, f)
  f.body = CreateFrame("Frame", nil, f)
  f.worth = buildWorth(f.body)
  -- UI/CraftQueueView.lua loads after this file; by the time the window opens it is there.
  if GC.CraftQueueView and GC.CraftQueueView.Build then GC.CraftQueueView.Build(f.body) end
  -- The recipes page hides on every close and every other tab, and the panel with it. On its way
  -- back every line it shows is drawn again, and one repaint on the next frame shows what changed
  -- meanwhile (the queue, crafted from the Orders page; the prices): none when the panel's own
  -- repaint shows it (P.Refresh).
  f:SetScript("OnShow", function(self)
    restamp(self)
    if self.worth:IsShown() then restampWorth(self.worth) end
    if not P._showing then P.Queue() end
  end)
  return f
end

-- Top to bottom: the header, This recipe when it shows, the tabs, and the view in what is left
-- above the foot.
function P.Layout()
  local f = P._frame
  local above = f.header
  if f.card:IsShown() then
    f.card:ClearAllPoints()
    f.card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -LAYOUT.GAP)
    above = f.card
  end
  f.switch:ClearAllPoints()
  f.switch:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  f.body:ClearAllPoints()
  f.body:SetPoint("TOPLEFT", f.switch, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -LAYOUT.PAD, LAYOUT.PAD + (f.footH or 0) + LAYOUT.GAP)
end

-- Everything but the view: the header, This recipe, the tabs and the foot, and the view's place.
local function paintTop(f)
  paintHeader(f)
  paintCard(f)
  paintSwitch(f)
  paintFoot(f)
  P.Layout()
end

--- Repaints the header, This recipe, the tabs and the foot, never the Worth crafting list: what
--- another reagent picked, a finished craft or the bags change.
function P.PaintOpen()
  local f = P._frame
  if not (f and f:IsVisible()) then return end
  paintTop(f)
end

--- One PaintOpen on the next frame, however many times this is asked for before then; none while
--- the panel is not on screen or a whole repaint is on its way.
function P.QueueOpen()
  local f = P._frame
  if P._pending or P._pendingOpen or not (f and f:IsVisible()) then return end
  P._pendingOpen = true
  after(function()
    P._pendingOpen = false
    P.PaintOpen()
  end)
end

--- Reads the window again and repaints the panel, or hides it. Nothing is read while the recipes
--- page is not on screen.
function P.Refresh()
  P._pending = false
  local f = P._frame
  local frame = window()
  if not (f and frame) then return end
  local page = frame.CraftingPage
  if not (type(page) == "table" and page:IsVisible()) then return end
  if not GC.CraftClient.IsOwnList() then
    f:Hide()
    return
  end
  f:SetHeight(frame:GetHeight())
  P._showing = true
  f:Show()
  P._showing = false
  paintTop(f)
  local qv = GC.CraftQueueView
  if P.View() == "queue" then
    f.worth:Hide()
    qv._frame:Show()
    qv.Refresh()
  else
    if qv and qv._frame then qv._frame:Hide() end
    local back = not f.worth:IsShown()
    f.worth:Show()
    P.PaintWorth()
    if back then restampWorth(f.worth) end
  end
end

--- One repaint on the next frame, however many times this is asked for before then.
function P.Queue()
  if P._pending then return end
  P._pending = true
  after(P.Refresh)
end

--- Builds the panel beside the window and listens for a selected recipe and another reagent
--- picked. Once: a later call only asks for a repaint.
function P.Attach()
  if P._frame then
    P.Queue()
    return
  end
  local frame = window()
  if not (frame and type(frame.CraftingPage) == "table") then return end
  P._frame = build(frame)
  local registry = _G.EventRegistry
  if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
    pcall(registry.RegisterCallback, registry, "ProfessionsRecipeListMixin.Event.OnRecipeSelected", P.Queue, P)
    for _, event in ipairs(OPEN_CALLBACKS) do pcall(registry.RegisterCallback, registry, event, P.QueueOpen, P) end
  end
  P.Queue()
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
  -- Every cast of the player's: a finished craft takes one off the queue (UI/CraftQueueView.lua),
  -- which This recipe and the Queue's count say.
  pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
  events:SetScript("OnEvent", function(_, event)
    -- Blizzard's own handler opens the window first: the panel attaches a frame later.
    if event == "TRADE_SKILL_SHOW" then
      after(P.Attach)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      if P._frame then P.QueueOpen() end
    elseif event == "BAG_UPDATE_DELAYED" then
      local qv = GC.CraftQueueView
      if P._frame and P.View() == "queue" and qv and qv.Queue then qv.Queue() end
    else
      P.Queue()
    end
  end)
  P._events = events
end
