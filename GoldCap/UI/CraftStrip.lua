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
GC.CraftStrip = GC.CraftStrip or {}
local S = GC.CraftStrip

local LAYOUT = { PAD = 10, GAP = 4, LINE_GAP = 2, TITLE = 12, BODY = 11, MIN_W = 260, MAX_W = 360, BELOW = 8 }

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

-- The lowest of the form's reagent blocks on screen: the strip goes under it. Region:GetBottom
-- decides where the client has laid them out; before it has, the last shown in the form's own
-- order. Auctionator's crafting strip, when it shows, sits there already, and this goes under it.
local function lowestBlock(form)
  local auctionator = _G.AuctionatorCraftingInfoProfessionsFrame
  if type(auctionator) == "table" and auctionator.IsShown and auctionator:IsShown() then return auctionator end
  local blocks = { form.Reagents, form.OptionalReagents }
  for _, extra in ipairs(type(form.extraSlotFrames) == "table" and form.extraSlotFrames or {}) do blocks[#blocks + 1] = extra end
  local last, lowest, lowestBottom, measured = nil, nil, nil, true
  for _, block in ipairs(blocks) do
    if type(block) == "table" and block.IsShown and block:IsShown() then
      last = block
      local bottom = block.GetBottom and block:GetBottom() or nil
      if type(bottom) ~= "number" then
        measured = false
      elseif lowestBottom == nil or bottom < lowestBottom then
        lowest, lowestBottom = block, bottom
      end
    end
  end
  if measured and lowest then return lowest end
  return last or form.Reagents
end

local function place(f, form)
  local below = lowestBlock(form)
  -- Left edge with the reagents, wherever the block above it starts.
  local dx = 0
  local reagents = form.Reagents
  if reagents and reagents.GetLeft and below.GetLeft then
    local a, b = reagents:GetLeft(), below:GetLeft()
    if type(a) == "number" and type(b) == "number" then dx = a - b end
  end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", below, "BOTTOMLEFT", dx, -LAYOUT.BELOW)
  local width = reagents and reagents.GetWidth and reagents:GetWidth() or 0
  width = math.min(LAYOUT.MAX_W, math.max(LAYOUT.MIN_W, tonumber(width) or 0))
  f:SetWidth(width)
  for _, line in ipairs(f.lines) do line:SetWidth(width - 2 * LAYOUT.PAD) end
end

local function paint(f, result)
  local T = GC.Theme
  local fg = T.color.fg
  for _, line in ipairs(f.lines) do
    line:SetTextColor(fg[1], fg[2], fg[3])
    line:Hide()
  end
  if result.missing then
    local names = {}
    for _, m in ipairs(result.missing) do names[#names + 1] = GC.CraftClient.MissingName(m) end
    f.lines[1]:SetText(GC.L["No GoldCap price for %s"]:format(table.concat(names, ", ")))
    f.lines[1]:Show()
    return 1
  end
  f.lines[1]:SetText(GC.L["Reagents cost %s"]:format(GC.Util.Money(result.cost)))
  f.lines[2]:SetText(GC.L["One craft sells for %s after the auction house cut"]:format(GC.Util.Money(result.sells)))
  f.lines[3]:SetText(GC.L["Profit %s"]:format(GC.Util.Money(result.profit)))
  local c = result.profit > 0 and T.color.green or (result.profit < 0 and T.color.red or fg)
  f.lines[3]:SetTextColor(c[1], c[2], c[3])
  for i = 1, 3 do f.lines[i]:Show() end
  return 3
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
  place(f, form)
  local shown = paint(f, GC.CraftClient.ProfitOf(recipe, open))
  -- The strip grows with its lines: every language's whole sentence shows, wrapped.
  local height = LAYOUT.PAD + f.title:GetHeight() + LAYOUT.GAP + LAYOUT.PAD
  for i = 1, shown do height = height + f.lines[i]:GetHeight() + (i > 1 and LAYOUT.LINE_GAP or 0) end
  f:SetHeight(height)
  f:Show()
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
