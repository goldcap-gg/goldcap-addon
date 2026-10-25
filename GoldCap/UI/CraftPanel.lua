local _, GC = ...

-- Retail's profession window: a GoldCap panel beside it, on the recipes page. Worth crafting lists
-- the recipes this character knows in the open profession that make a profit, by profit per craft,
-- each reagent at its cheapest priced quality, with how many of its item sell a day where that is
-- known, and marks a recipe whose item sells under once a day. A recipe that makes no profit, and
-- one GoldCap cannot price (a reagent or what it makes has no price), are each counted under the
-- list, never listed.
--
-- The panel is a frame of its own, a child of the crafting page so it goes with the page, and it
-- leaves Blizzard's frames as they are: no hook, no method replaced. It shows only for the
-- character's own recipes, never a guild's, a linked list or an NPC's. Its events are its own
-- (Core/Collection.lua's shape: each registered under pcall), so Core/Init.lua is not touched.
GC.CraftPanel = GC.CraftPanel or {}
local P = GC.CraftPanel

local LAYOUT = {
  WIDTH = 300, PAD = 10, GAP = 6, LINE_GAP = 2, TITLE = 12, HEAD = 12, NAME = 11, SMALL = 10,
  ROW_PAD = 4, BAR = 16, PROFIT_GAP = 8, NAME_MIN = 80,
  CARD_PAD = 8, BUTTON_H = 24, BUTTON_GAP = 8, BUTTON_MIN = 72, SEG_PAD = 2, SEG_MIN = 60,
}
LAYOUT.INNER = LAYOUT.WIDTH - 2 * LAYOUT.PAD
LAYOUT.ROW_W = LAYOUT.INNER - LAYOUT.BAR
-- The width a view in the panel's body draws in (UI/CraftQueueView.lua).
P.BODY_W = LAYOUT.INNER

-- What changes the list: the window opening, its recipe list refreshed, a recipe learned. Bags
-- changing moves nothing in Worth crafting, but the queue reads them (UI/CraftQueueView.lua): a
-- bag change repaints that view alone, never the whole list, which fires on every craft of a
-- Create All.
local EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED", "BAG_UPDATE_DELAYED" }

local function window()
  local frame = _G.ProfessionsFrame
  return type(frame) == "table" and frame or nil
end

local function after(fn)
  local timer = _G.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, fn) else fn() end
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function wrapped(parent, size, width)
  local fs = GC.Theme.Label(parent, size)
  fs:SetWordWrap(true)
  fs:SetWidth(width)
  return fs
end

-- ---------------------------------------------------------------------------------------------
-- Worth crafting
-- ---------------------------------------------------------------------------------------------

local function buildWorth(body)
  local T = GC.Theme
  local v = CreateFrame("Frame", nil, body)
  v:SetAllPoints(body)
  v.heading = T.Heading(v, LAYOUT.HEAD)
  v.heading:SetJustifyH("LEFT")
  v.heading:SetWordWrap(true)
  v.heading:SetWidth(LAYOUT.INNER)
  v.heading:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
  setColor(v.heading, T.color.gold)
  v.empty = wrapped(v, LAYOUT.NAME, LAYOUT.INNER)
  v.empty:SetPoint("TOPLEFT", v.heading, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  setColor(v.empty, T.color.fgMuted)
  v.note = wrapped(v, LAYOUT.SMALL, LAYOUT.INNER)
  v.note:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 0, 0)
  setColor(v.note, T.color.fgDim)
  v.unpriced = wrapped(v, LAYOUT.SMALL, LAYOUT.INNER)
  v.unpriced:SetPoint("BOTTOMLEFT", v.note, "TOPLEFT", 0, LAYOUT.LINE_GAP)
  setColor(v.unpriced, T.color.fgMuted)
  v.unprofitable = wrapped(v, LAYOUT.SMALL, LAYOUT.INNER)
  setColor(v.unprofitable, T.color.fgMuted)
  v.scroll = CreateFrame("ScrollFrame", nil, v, "UIPanelScrollFrameTemplate")
  if T.QuietScrollBar then T.QuietScrollBar(v.scroll) end
  v.content = CreateFrame("Frame", nil, v.scroll)
  v.content:SetSize(LAYOUT.ROW_W, 1)
  v.scroll:SetScrollChild(v.content)
  v.rows = {}
  return v
end

local function newRow(v, index)
  local T = GC.Theme
  local frame = CreateFrame("Button", nil, v.content)
  frame:SetWidth(LAYOUT.ROW_W)
  local row = { frame = frame }
  if index % 2 == 0 then
    row.bg = frame:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(frame)
    local z = T.color.zebra
    row.bg:SetColorTexture(z[1], z[2], z[3], z[4])
  end
  -- The profit is one line and never cut: a FontString with no width of its own is as wide as
  -- its text (coins included), and the name wraps in what is left beside it.
  row.profit = T.Num(frame, LAYOUT.NAME)
  row.profit:SetWordWrap(false)
  row.profit:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -LAYOUT.ROW_PAD)
  row.name = wrapped(frame, LAYOUT.NAME, LAYOUT.ROW_W)
  row.name:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -LAYOUT.ROW_PAD)
  setColor(row.name, T.color.fg)
  row.pace = wrapped(frame, LAYOUT.SMALL, LAYOUT.ROW_W)
  setColor(row.pace, T.color.fgMuted)
  row.slow = wrapped(frame, LAYOUT.SMALL, LAYOUT.ROW_W)
  local warn = GC.Kit and GC.Kit.Tokens and GC.Kit.Tokens.color and GC.Kit.Tokens.color.warn or T.color.fgMuted
  setColor(row.slow, warn)
  -- A right click offers to queue the row's recipe (UI/BuyLists.lua's menu, in the client's font).
  frame:RegisterForClicks("RightButtonUp")
  frame:SetScript("OnClick", function(self, button)
    if button == "RightButton" and row.data then P.OpenRowMenu(self, row.data.recipe) end
  end)
  return row
end

local function paintRow(row, data, previous)
  local T = GC.Theme
  local profit = data.result.profit
  row.profit:SetText(GC.Util.Money(profit))
  setColor(row.profit, profit > 0 and T.color.green or (profit < 0 and T.color.red or T.color.fg))
  row.name:SetText(data.name)
  row.name:SetWidth(math.max(LAYOUT.NAME_MIN, LAYOUT.ROW_W - (row.profit:GetStringWidth() or 0) - LAYOUT.PROFIT_GAP))
  -- Top to bottom: the name beside the profit, then how many sell a day or the slow mark under
  -- them (never both: a slow seller sells under one a day), each line as tall as its wrapped text.
  local y = LAYOUT.ROW_PAD + math.max(row.name:GetHeight(), row.profit:GetHeight())
  local sold, pace = data.sold, nil
  if type(sold) == "number" and not GC.CraftMath.IsSlow(sold) then
    pace = GC.L["Sells about %s a day"]:format(GC.Util.Grouped(sold))
  end
  for _, part in ipairs({
    { fs = row.pace, text = pace },
    { fs = row.slow, text = GC.CraftMath.IsSlow(data.sold) and GC.L["Slow seller"] or nil },
  }) do
    if part.text then
      part.fs:SetText(part.text)
      part.fs:ClearAllPoints()
      part.fs:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, -(y + LAYOUT.LINE_GAP))
      part.fs:Show()
      y = y + LAYOUT.LINE_GAP + part.fs:GetHeight()
    else
      part.fs:Hide()
    end
  end
  row.frame:SetHeight(y + LAYOUT.ROW_PAD)
  row.frame:ClearAllPoints()
  if previous then
    row.frame:SetPoint("TOPLEFT", previous.frame, "BOTTOMLEFT", 0, 0)
  else
    row.frame:SetPoint("TOPLEFT", P._frame.worth.content, "TOPLEFT", 0, 0)
  end
  row.data = data
  row.frame:Show()
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
  local v = P._frame.worth
  v.heading:SetText(GC.L["Worth crafting"])
  local ranked, unpriced, unprofitable = P.Rows()
  P._rows = ranked
  local previous, total = nil, 0
  for i, data in ipairs(ranked) do
    local row = v.rows[i] or newRow(v, i)
    v.rows[i] = row
    paintRow(row, data, previous)
    data.widget = row
    total = total + row.frame:GetHeight()
    previous = row
  end
  for i = #ranked + 1, #v.rows do v.rows[i].frame:Hide() end
  v.content:SetHeight(math.max(1, total))

  if #ranked == 0 then
    v.empty:SetText(unprofitable > 0 and GC.L["No recipe here makes a profit now"]
      or GC.L["No recipe here has a GoldCap price yet"])
    v.empty:Show()
    v.scroll:Hide()
  else
    v.empty:Hide()
    v.scroll:Show()
  end
  v.note:SetText(GC.L["Each reagent at its cheapest quality"])
  local footer = v.note:GetHeight()
  if unpriced > 0 then
    v.unpriced:SetText(unpriced == 1 and GC.L["1 recipe has no GoldCap price for a reagent or what it makes"]
      or GC.L["%d recipes have no GoldCap price for a reagent or what it makes"]:format(unpriced))
    v.unpriced:Show()
    footer = footer + LAYOUT.LINE_GAP + v.unpriced:GetHeight()
  else
    v.unpriced:Hide()
  end
  -- Under an empty list the empty line already says that no recipe makes a profit.
  if unprofitable > 0 and #ranked > 0 then
    v.unprofitable:SetText(unprofitable == 1 and GC.L["1 recipe makes no profit now"]
      or GC.L["%d recipes make no profit now"]:format(unprofitable))
    v.unprofitable:ClearAllPoints()
    v.unprofitable:SetPoint("BOTTOMLEFT", unpriced > 0 and v.unpriced or v.note, "TOPLEFT", 0, LAYOUT.LINE_GAP)
    v.unprofitable:Show()
    footer = footer + LAYOUT.LINE_GAP + v.unprofitable:GetHeight()
  else
    v.unprofitable:Hide()
  end
  -- The list takes what the heading and the footer leave, both as tall as their wrapped text.
  v.scroll:ClearAllPoints()
  v.scroll:SetPoint("TOPLEFT", v.heading, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  v.scroll:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -LAYOUT.BAR, footer + LAYOUT.GAP)
end

-- ---------------------------------------------------------------------------------------------
-- This recipe: putting the open recipe in the queue
-- ---------------------------------------------------------------------------------------------

local function queueChanged()
  if P.OnQueueChanged then P.OnQueueChanged() end
  P.Queue()
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
    onCommit = function(n)
      GC.CraftQueue.Add(char, recipe, n)
      queueChanged()
    end,
  })
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

local function buildCard(f)
  local T = GC.Theme
  local card = T.Card(f, T.color.panelHi, T.color.border, true)
  card:SetWidth(LAYOUT.INNER)
  local inner = LAYOUT.INNER - 2 * LAYOUT.CARD_PAD
  card.heading = wrapped(card, LAYOUT.SMALL, inner)
  card.heading:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.CARD_PAD, -LAYOUT.CARD_PAD)
  setColor(card.heading, T.color.fgDim)
  card.name = wrapped(card, LAYOUT.NAME, inner)
  card.name:SetPoint("TOPLEFT", card.heading, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  setColor(card.name, T.color.fg)
  -- The strip's lines when there is no room for them under the reagents (UI/CraftStrip.lua).
  card.figures = {}
  card.add = T.Button(card, "primary", "plaque")
  card.add:SetHeight(LAYOUT.BUTTON_H)
  card.add:SetScript("OnClick", function(self) if card.recipe then P.AskCount(self, card.recipe) end end)
  card.restock = T.Button(card, "primary", "plaque")
  card.restock:SetHeight(LAYOUT.BUTTON_H)
  card.restock:SetScript("OnClick", function(self) if card.recipe then P.AskRestock(self, card.recipe) end end)
  card:Hide()
  return card
end

-- The card for the recipe the window shows. It has the strip's lines when the strip found no room
-- under the reagents (UI/CraftStrip.lua), and Add to queue and Restock to when the recipe can be
-- queued: never for a recipe the character has not learned (Blizzard's list shows those too: one
-- could never be crafted from the queue), nor without a character or with a store a newer GoldCap
-- wrote. With neither, or no recipe GoldCap prices, it is hidden. Each button is as wide as its
-- label in the player's language; the two sit side by side when both fit the card, else one
-- under the other.
local function paintCard(f)
  local card = f.card
  local CC = GC.CraftClient
  local open = CC.OpenRecipe()
  local recipe = open and CC.Snapshot(open.recipeID) or nil
  local strip = GC.CraftStrip
  local figures = recipe and strip and strip.Folded and strip.Folded(open.recipeID) or nil
  local queueable = recipe ~= nil and open.learned == true and CC.Char() ~= nil and GC.CraftQueue.Writable()
  card.recipe = queueable and recipe or nil
  if not (queueable or figures) then
    card:Hide()
    return
  end
  card.heading:SetText(GC.L["This recipe"])
  card.name:SetText(recipe.name)
  local inner = LAYOUT.INNER - 2 * LAYOUT.CARD_PAD
  local height = LAYOUT.CARD_PAD + card.heading:GetHeight() + LAYOUT.LINE_GAP + card.name:GetHeight()
  local above = card.name
  -- The strip's lines, each wrapped in the card and as tall as its text.
  local lines = figures or {}
  for i, l in ipairs(lines) do
    local fs = card.figures[i]
    if not fs then
      fs = wrapped(card, LAYOUT.NAME, inner)
      card.figures[i] = fs
    end
    fs:SetText(l.text)
    setColor(fs, l.color)
    local gap = i == 1 and LAYOUT.GAP or LAYOUT.LINE_GAP
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
    fs:Show()
    height = height + gap + fs:GetHeight()
    above = fs
  end
  for i = #lines + 1, #card.figures do card.figures[i]:Hide() end
  if queueable then
    card.add:SetLabel(GC.L["Add to queue"])
    card.restock:SetLabel(GC.L["Restock to"])
    card.add:FitLabels({ card.add.label }, LAYOUT.BUTTON_MIN)
    card.restock:FitLabels({ card.restock.label }, LAYOUT.BUTTON_MIN)
    local beside = card.add:GetWidth() + LAYOUT.BUTTON_GAP + card.restock:GetWidth() <= inner
    card.add:ClearAllPoints()
    card.add:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -LAYOUT.GAP)
    card.restock:ClearAllPoints()
    if beside then
      card.restock:SetPoint("LEFT", card.add, "RIGHT", LAYOUT.BUTTON_GAP, 0)
    else
      card.restock:SetPoint("TOPLEFT", card.add, "BOTTOMLEFT", 0, -LAYOUT.BUTTON_GAP)
    end
    card.add:Show()
    card.restock:Show()
    height = height + LAYOUT.GAP + (beside and LAYOUT.BUTTON_H or (2 * LAYOUT.BUTTON_H + LAYOUT.BUTTON_GAP))
  else
    card.add:Hide()
    card.restock:Hide()
  end
  card:SetHeight(height + LAYOUT.CARD_PAD)
  card:Show()
end

--- Repaints This recipe alone, and what sits under it: the strip calls this when it hands its
--- lines over for want of room under the reagents, or takes them back.
function P.PaintOpen()
  local f = P._frame
  if not (f and f:IsVisible()) then return end
  paintCard(f)
  P.Layout()
end

-- ---------------------------------------------------------------------------------------------
-- The view switch: Worth crafting or the Queue (UI/CraftQueueView.lua), for this session
-- ---------------------------------------------------------------------------------------------

--- The view the body shows: "queue" once the player picked it and the Queue view is there.
function P.View()
  local qv = GC.CraftQueueView
  if P._view == "queue" and qv and qv._frame then return "queue" end
  return "worth"
end

-- The Sell tab's deck switch (UI/Sell/Toolbar.lua): a sunken track, the view that is on lit and
-- the other bare text.
local function buildSwitch(f)
  local T = GC.Theme
  local sw = CreateFrame("Frame", nil, f)
  sw.track = T.SlicedTexture(sw, "BACKGROUND", T.MEDIA .. "plaque.png", { 0, 0, 0, 0.3 }, 12)
  sw.track:SetAllPoints(sw)
  for _, id in ipairs({ "worth", "queue" }) do
    local b = T.Button(sw, "segment", "plaque")
    b:SetHeight(LAYOUT.BUTTON_H - 2 * LAYOUT.SEG_PAD)
    b:SetScript("OnClick", function()
      P._view = id
      P.Refresh()
    end)
    sw[id] = b
  end
  return sw
end

-- Each half as wide as its label in the player's language; one under the other when the two do
-- not fit the panel side by side.
local function paintSwitch(f)
  local sw = f.switch
  local view = P.View()
  sw.worth:SetLabel(GC.L["Worth crafting"])
  sw.queue:SetLabel(GC.L["Queue"])
  for _, id in ipairs({ "worth", "queue" }) do
    sw[id]:FitLabels({ sw[id].label }, LAYOUT.SEG_MIN)
    sw[id]:SetVariant(id == view and "active" or "segment")
  end
  local pad, h = LAYOUT.SEG_PAD, LAYOUT.BUTTON_H - 2 * LAYOUT.SEG_PAD
  local a, b = sw.worth:GetWidth(), sw.queue:GetWidth()
  sw.worth:ClearAllPoints()
  sw.worth:SetPoint("TOPLEFT", sw, "TOPLEFT", pad, -pad)
  sw.queue:ClearAllPoints()
  if a + b + 3 * pad <= LAYOUT.INNER then
    sw.queue:SetPoint("LEFT", sw.worth, "RIGHT", pad, 0)
    sw:SetSize(a + b + 3 * pad, h + 2 * pad)
  else
    sw.queue:SetPoint("TOPLEFT", sw.worth, "BOTTOMLEFT", 0, -pad)
    sw:SetSize(math.max(a, b) + 2 * pad, 2 * h + 3 * pad)
  end
end

-- ---------------------------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------------------------

local function build(frame)
  local T = GC.Theme
  local f = T.Card(frame.CraftingPage, T.color.panel, T.color.border)
  f:SetWidth(LAYOUT.WIDTH)
  f:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
  -- The recipes page is 942 wide: on a 16:10 or 4:3 screen, or with the window pushed to the
  -- centre, the panel's right edge (the profit column) would fall off the screen. Clamped, the
  -- client slides it back over the window instead. Blizzard's own UI panel width is left alone.
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f.title = T.Label(f, LAYOUT.TITLE)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  setColor(f.title, T.color.gold)
  f.title:SetText("GoldCap")
  f.card = buildCard(f)
  f.switch = buildSwitch(f)
  f.body = CreateFrame("Frame", nil, f)
  f.worth = buildWorth(f.body)
  -- UI/CraftQueueView.lua loads after this file; by the time the window opens it is there.
  if GC.CraftQueueView and GC.CraftQueueView.Build then GC.CraftQueueView.Build(f.body) end
  return f
end

-- Top to bottom: the title, This recipe when it shows, the view switch, and the view in the rest
-- of the panel.
function P.Layout()
  local f = P._frame
  local above = f.title
  if f.card:IsShown() then
    f.card:ClearAllPoints()
    f.card:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -LAYOUT.GAP)
    above = f.card
  end
  f.switch:ClearAllPoints()
  f.switch:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  above = f.switch
  f.body:ClearAllPoints()
  f.body:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -LAYOUT.PAD, LAYOUT.PAD)
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
  f:Show()
  paintCard(f)
  paintSwitch(f)
  P.Layout()
  local qv = GC.CraftQueueView
  if P.View() == "queue" then
    f.worth:Hide()
    qv._frame:Show()
    qv.Refresh()
  else
    if qv and qv._frame then qv._frame:Hide() end
    f.worth:Show()
    P.PaintWorth()
  end
end

--- One repaint on the next frame, however many times this is asked for before then.
function P.Queue()
  if P._pending then return end
  P._pending = true
  after(P.Refresh)
end

--- Builds the panel beside the window and listens for a selected recipe. Once: a later call only
--- asks for a repaint.
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
  end
  P.Queue()
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
  events:SetScript("OnEvent", function(_, event)
    -- Blizzard's own handler opens the window first: the panel attaches a frame later.
    if event == "TRADE_SKILL_SHOW" then
      after(P.Attach)
    elseif event == "BAG_UPDATE_DELAYED" then
      local qv = GC.CraftQueueView
      if P._frame and P.View() == "queue" and qv and qv.Queue then qv.Queue() end
    else
      P.Queue()
    end
  end)
  P._events = events
end
