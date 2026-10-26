local _, GC = ...

-- Retail's profession window: a GoldCap strip under the open recipe's reagents. What the reagents
-- the player picked cost (a slot with nothing allocated at its cheapest priced quality), what one
-- craft sells for after the auction house cut, and the profit. A reagent or a crafted item with no
-- GoldCap price is named instead of a number: an invented figure is worse than none
-- (Core/CraftMath.lua).
--
-- Read-only, and it leaves Blizzard's frames as they are: no hook, no method replaced, no field
-- set on them. The strip is a frame of its own made a child of the recipe form, so it shows and
-- hides with the recipes page. What changes the figures reaches it through EventRegistry
-- callbacks (Blizzard runs them through securecallfunction), each one asking for a single repaint
-- on the next frame however many fire together.
--
-- It never draws over the form's own controls. It goes under the lowest block on screen and must
-- end above the "Use Best Quality Reagents" checkbox and the form's bottom edge (the page's Create
-- buttons are under it), and left of the Details column where that reaches down beside it. A
-- recipe with many slots, Auctionator's strip, or the minimized window can leave no such room:
-- then the strip hides. The panel's This recipe card (UI/CraftPanel.lua) shows the same three
-- figures whether the strip shows or not, and names what has no price in the strip's words (S.Lines).
GC.CraftStrip = GC.CraftStrip or {}
local S = GC.CraftStrip

local LAYOUT = { PAD = 10, GAP = 4, LINE_GAP = 2, TITLE = 12, BODY = 11, MIN_W = 260, MAX_W = 360, BELOW = 8,
  CLEAR = 4 }

-- What changes the open recipe's figures: another recipe picked, another reagent allocated, the
-- transaction rebuilt, another profession opened (Blizzard_ProfessionsTransaction.lua,
-- Blizzard_ProfessionsRecipeList.lua, Blizzard_ProfessionsFrame.lua).
local CALLBACKS = {
  "ProfessionsRecipeListMixin.Event.OnRecipeSelected", "Professions.AllocationUpdated",
  "Professions.TransactionUpdated", "Professions.ProfessionSelected",
}

local function build(form)
  local T = GC.Theme
  local f = T.Card(form, T.color.panel, T.color.border, true)
  f.title = T.Label(f, LAYOUT.TITLE)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  f.title:SetTextColor(T.color.gold[1], T.color.gold[2], T.color.gold[3])
  f.title:SetText("GoldCap")
  f.lines = {}
  for i = 1, 3 do
    local line = T.Label(f, LAYOUT.BODY)
    line:SetWordWrap(true)
    line:SetPoint("TOPLEFT", i == 1 and f.title or f.lines[i - 1], "BOTTOMLEFT", 0, -(i == 1 and LAYOUT.GAP or LAYOUT.LINE_GAP))
    f.lines[i] = line
  end
  return f
end

local function isShown(region)
  return type(region) == "table" and type(region.IsShown) == "function" and region:IsShown() == true
end

-- Region:GetLeft / GetTop / GetBottom, in UI units (bottom up), or nil before the client has
-- laid the region out.
local function edge(region, name)
  local fn = type(region) == "table" and region[name] or nil
  if type(fn) ~= "function" then return nil end
  local v = fn(region)
  return type(v) == "number" and v or nil
end

-- What the strip goes under, in the order the form lays it out: the reagent blocks, the recraft,
-- salvage and enchant slots, Finishing reagents and the Concentrate button (the minimized window
-- puts both under the reagents), and Auctionator's crafting strip, which hangs under the reagents
-- when it shows (Auctionator's Source_Mainline/CraftingInfo/Professions.lua).
local function blocks(form)
  local list = { form.Reagents, form.OptionalReagents }
  for _, extra in ipairs(type(form.extraSlotFrames) == "table" and form.extraSlotFrames or {}) do list[#list + 1] = extra end
  for _, block in ipairs({ form.FinishingReagents, form.Concentrate, _G.AuctionatorCraftingInfoProfessionsFrame }) do
    list[#list + 1] = block
  end
  return list
end

-- The lowest of those on screen, and whether every one shown has been laid out. Before the client
-- has laid them out, the last shown in that order.
local function lowestBlock(form)
  local last, lowest, lowestBottom, measured = nil, nil, nil, true
  for _, block in ipairs(blocks(form)) do
    if isShown(block) then
      last = block
      local bottom = edge(block, "GetBottom")
      if not bottom then
        measured = false
      elseif lowestBottom == nil or bottom < lowestBottom then
        lowest, lowestBottom = block, bottom
      end
    end
  end
  if measured and lowest then return lowest, true end
  return last or form.Reagents, false
end

-- The room under `below`: { top, floor, maxWidth }, the strip's top edge, the lowest its bottom
-- edge may go, and the widest it may be. nil when the client has not laid out what decides it.
-- The floor is the form's bottom edge, or the top of "Use Best Quality Reagents" when it shows
-- (BOTTOMLEFT 30, 20, Blizzard_ProfessionsRecipeSchematicForm.xml); the width stops short of the
-- Details column where that reaches down beside the strip.
local function room(form, below)
  local bottom, left, floor = edge(below, "GetBottom"), edge(form.Reagents, "GetLeft"), edge(form, "GetBottom")
  if not (bottom and left and floor) then return nil end
  local checkbox = form.AllocateBestQualityCheckbox
  if isShown(checkbox) then
    local top = edge(checkbox, "GetTop")
    if not top then return nil end
    floor = math.max(floor, top)
  end
  local top = bottom - LAYOUT.BELOW
  local maxWidth = LAYOUT.MAX_W
  local details = form.Details
  if isShown(details) then
    local dBottom, dLeft = edge(details, "GetBottom"), edge(details, "GetLeft")
    if not (dBottom and dLeft) then return nil end
    if dBottom < top then maxWidth = math.min(maxWidth, dLeft - LAYOUT.CLEAR - left) end
  end
  return { top = top, floor = floor + LAYOUT.CLEAR, maxWidth = maxWidth }
end

-- Anchors the strip under the lowest block, at the reagents' left edge, as wide as the reagents
-- (within MIN_W and MAX_W and the room beside it). Answers the room, or nil when there is none
-- to measure or it is narrower than MIN_W.
local function place(f, form)
  local below, measured = lowestBlock(form)
  local reagents = form.Reagents
  local a, b = edge(reagents, "GetLeft"), edge(below, "GetLeft")
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", below, "BOTTOMLEFT", (a and b) and (a - b) or 0, -LAYOUT.BELOW)
  local space = measured and room(form, below) or nil
  if space and space.maxWidth < LAYOUT.MIN_W then space = nil end
  local width = isShown(reagents) and tonumber(reagents:GetWidth()) or 0
  width = math.min(LAYOUT.MAX_W, math.max(LAYOUT.MIN_W, width or 0))
  if space then width = math.min(width, space.maxWidth) end
  f:SetWidth(width)
  for _, line in ipairs(f.lines) do line:SetWidth(width - 2 * LAYOUT.PAD) end
  return space
end

--- The lines the strip shows for a ProfitOf result: { { text = ..., color = { r, g, b } }, ... }.
function S.Lines(result)
  local T = GC.Theme
  local fg = T.color.fg
  if result.missing then
    local names = {}
    for _, m in ipairs(result.missing) do names[#names + 1] = GC.CraftClient.MissingName(m) end
    return { { text = GC.L["No GoldCap price for %s"]:format(table.concat(names, ", ")), color = fg } }
  end
  return {
    { text = GC.L["Reagents cost %s"]:format(GC.Util.Money(result.cost)), color = fg },
    { text = GC.L["One craft sells for %s after the auction house cut"]:format(GC.Util.Money(result.sells)), color = fg },
    { text = GC.L["Profit %s"]:format(GC.Util.Money(result.profit)),
      color = result.profit > 0 and T.color.green or (result.profit < 0 and T.color.red or fg) },
  }
end

local function paint(f, lines)
  for i, line in ipairs(f.lines) do
    local l = lines[i]
    if l then
      line:SetText(l.text)
      line:SetTextColor(l.color[1], l.color[2], l.color[3])
      line:Show()
    else
      line:Hide()
    end
  end
  return #lines
end

--- Reads the open recipe again and repaints the strip, or hides it.
function S.Refresh()
  S._pending = false
  local f = S._frame
  if not f then return end
  local open = GC.CraftClient.OpenRecipe()
  local recipe = open and GC.CraftClient.Snapshot(open.recipeID) or nil
  if not recipe then
    f:Hide()
    return
  end
  local form = GC.CraftClient.Form()
  local lines = S.Lines(GC.CraftClient.ProfitOf(recipe, open))
  -- Measured under pcall: a layout the client answers oddly for is no room, never an error.
  local ok, space = pcall(place, f, form)
  local shown = paint(f, lines)
  -- The strip grows with its lines: every language's whole sentence shows, wrapped.
  local height = LAYOUT.PAD + f.title:GetHeight() + LAYOUT.GAP + LAYOUT.PAD
  for i = 1, shown do height = height + f.lines[i]:GetHeight() + (i > 1 and LAYOUT.LINE_GAP or 0) end
  f:SetHeight(height)
  f:SetShown(ok and space ~= nil and space.top - height >= space.floor)
end

--- One repaint on the next frame, however many times this is asked for before then.
function S.Queue()
  if S._pending then return end
  S._pending = true
  local timer = _G.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(0, S.Refresh)
  else
    S.Refresh()
  end
end

--- Builds the strip on the recipe form and listens for what changes it. Once: a later call only
--- asks for a repaint.
function S.Attach()
  if S._frame then
    S.Queue()
    return
  end
  local form = GC.CraftClient.Form()
  if not form then return end
  S._frame = build(form)
  -- Minimizing or maximizing the window resizes the form (395 or 655 wide) and moves the blocks
  -- the strip measures, with none of the callbacks below when the player allocated by hand: a
  -- frame of GoldCap's own over the form asks for a repaint when its size changes.
  local watch = CreateFrame("Frame", nil, form)
  watch:SetAllPoints(form)
  watch:SetScript("OnSizeChanged", function() S.Queue() end)
  S._watch = watch
  local registry = _G.EventRegistry
  if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
    for _, event in ipairs(CALLBACKS) do pcall(registry.RegisterCallback, registry, event, S.Queue, S) end
  end
  S.Queue()
end

-- TRADE_SKILL_SHOW: Blizzard's own handler loads and opens the profession window, so the strip
-- attaches a frame later, once the form is there.
if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "TRADE_SKILL_SHOW")
  events:SetScript("OnEvent", function()
    local timer = _G.C_Timer
    if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, S.Attach) else S.Attach() end
  end)
  S._events = events
end
