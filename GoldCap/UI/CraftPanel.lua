local _, GC = ...

-- Retail's profession window: a GoldCap panel beside it, on the recipes page. Worth crafting lists
-- the recipes this character knows in the open profession by profit per craft, each reagent at its
-- cheapest priced quality, with the profit an hour where the market's daily sales are known, and
-- marks a recipe whose item sells under once a day. A recipe GoldCap cannot price (a reagent or
-- what it makes has no price) is counted under the list, never ranked as 0 profit.
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
}
LAYOUT.INNER = LAYOUT.WIDTH - 2 * LAYOUT.PAD
LAYOUT.ROW_W = LAYOUT.INNER - LAYOUT.BAR

-- What changes the list: the window opening, its recipe list refreshed, a recipe learned, bags
-- changed (a reagent bought or used moves nothing here, but the queue reads them: UI/CraftQueueView).
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
  row.hour = wrapped(frame, LAYOUT.SMALL, LAYOUT.ROW_W)
  setColor(row.hour, T.color.fgMuted)
  row.slow = wrapped(frame, LAYOUT.SMALL, LAYOUT.ROW_W)
  local warn = GC.Kit and GC.Kit.Tokens and GC.Kit.Tokens.color and GC.Kit.Tokens.color.warn or T.color.fgMuted
  setColor(row.slow, warn)
  return row
end

local function paintRow(row, data, previous)
  local T = GC.Theme
  local profit = data.result.profit
  row.profit:SetText(GC.Util.Money(profit))
  setColor(row.profit, profit > 0 and T.color.green or (profit < 0 and T.color.red or T.color.fg))
  row.name:SetText(data.name)
  row.name:SetWidth(math.max(LAYOUT.NAME_MIN, LAYOUT.ROW_W - (row.profit:GetStringWidth() or 0) - LAYOUT.PROFIT_GAP))
  -- Top to bottom: the name beside the profit, then profit an hour and the slow mark under them,
  -- each line as tall as its wrapped text.
  local y = LAYOUT.ROW_PAD + math.max(row.name:GetHeight(), row.profit:GetHeight())
  local perHour = GC.CraftMath.PerHour(profit, data.sold, data.recipe and data.recipe.per or 1)
  for _, part in ipairs({
    { fs = row.hour, text = perHour and GC.L["%s an hour"]:format(GC.Util.Money(perHour)) or nil },
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

--- Worth crafting's rows: every known recipe GoldCap can price, by profit per craft, and how many
--- it could not price.
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
  local ranked, unpriced = P.Rows()
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
    v.empty:SetText(GC.L["No recipe here has a GoldCap price yet"])
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
  -- The list takes what the heading and the footer leave, both as tall as their wrapped text.
  v.scroll:ClearAllPoints()
  v.scroll:SetPoint("TOPLEFT", v.heading, "BOTTOMLEFT", 0, -LAYOUT.GAP)
  v.scroll:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -LAYOUT.BAR, footer + LAYOUT.GAP)
end

-- ---------------------------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------------------------

local function build(frame)
  local T = GC.Theme
  local f = T.Card(frame.CraftingPage, T.color.panel, T.color.border)
  f:SetWidth(LAYOUT.WIDTH)
  f:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
  f:EnableMouse(true)
  f.title = T.Label(f, LAYOUT.TITLE)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  setColor(f.title, T.color.gold)
  f.title:SetText("GoldCap")
  f.body = CreateFrame("Frame", nil, f)
  f.worth = buildWorth(f.body)
  return f
end

-- The view takes the panel under its title.
function P.Layout()
  local f = P._frame
  f.body:ClearAllPoints()
  f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -LAYOUT.GAP)
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
  P.Layout()
  P.PaintWorth()
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
    if event == "TRADE_SKILL_SHOW" then after(P.Attach) else P.Queue() end
  end)
  P._events = events
end
