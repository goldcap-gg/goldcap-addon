local _, GC = ...

-- Retail's Worth crafting for items sold per piece (gear, tools, bags). Loaded by GoldCap.toc alone,
-- right after UI/CraftPanel.lua, whose fields it replaces; WoW: Forever never loads it and keeps its
-- own (UI/CraftPanel_Camelot.lua).
--
-- Such an item is priced at what the version the character makes sold for this week
-- (Services/CraftClient.lua's SellOf, `basis`), never at the region's listed median. Worth crafting
-- reads in two groups (P.Rows): the recipes a proven price or the market says make a profit, then,
-- for learned recipes alone and behind the switch beside "Unlearned recipes too" (P.ShowsUnproven),
-- those whose version has no proven price, under No estimate, with what is known of it. A row's
-- tooltip, This recipe and the strip say what the price rests on (GC.CraftVersion.Lines).
local P, S = GC.CraftPanel, GC.CraftStrip
local Money = GC.Util.Money

local retailRowTip, retailLines = P.RowTip, S.Lines

-- What a result's price basis says, a line each (none for the market's).
local function versionLines(result)
  return GC.CraftVersion.Lines(type(result) == "table" and result.basis or nil, Money)
end

-- Which group a recipe's result goes in: "main" for a proven price or the market's, "none" for an
-- item sold per piece whose version has none.
local function groupOf(result)
  local kind = type(result) == "table" and type(result.basis) == "table" and result.basis.kind or nil
  if kind == nil or kind == "proven" or kind == "market" then return "main" end
  return "none"
end

local function byName(a, b)
  local an, bn = tostring(a.name or ""), tostring(b.name or "")
  if an ~= bn then return an < bn end
  return (a.recipeID or 0) < (b.recipeID or 0)
end

-- What a craft would make at a thin version's few sales, when its reagents are priced.
local function thinProfit(row)
  local r, b = row.result, row.result.basis
  if b.kind ~= "thin" or type(r.cost) ~= "number" or type(b.median) ~= "number" then return nil end
  return math.floor(b.median * 0.95) * math.max(1, row.recipe.per or 1) - r.cost
end

-- The no-estimate order: a version that sold a few times first (by what a craft would make at its
-- price, where that is known), then one that did not sell, one the game did not name, an item that
-- sold nothing and one with no sales to read, each by name.
local TIER = { thin = 1, unsold = 2, unknown = 3, nosales = 4, nodata = 5 }

local function noneOrder(a, b)
  local ta, tb = TIER[a.result.basis.kind] or 6, TIER[b.result.basis.kind] or 6
  if ta ~= tb then return ta < tb end
  local pa, pb = a.thin, b.thin
  if pa ~= pb then
    if pa == nil or pb == nil then return pb == nil end
    return pa > pb
  end
  return byName(a, b)
end

--- Worth crafting's rows, each with its `group`: "main" the recipes a proven or market price says
--- make a profit, by profit per craft; then, with P.ShowsUnproven and for learned recipes alone,
--- "none" those whose version has no proven price. Answers them with how many have no price and how
--- many make no profit: a learned recipe the switch hides counts as having no price. A recipe not
--- learned is listed in the first group for its profit alone, and counted nowhere.
function P.Rows()
  local CC = GC.CraftClient
  local unproven = P.ShowsUnproven()
  local main, none, hidden = {}, {}, 0
  local ids, unlearned = CC.KnownRecipes(P.ShowsUnlearned())
  for _, id in ipairs(ids) do
    local recipe = CC.Snapshot(id)
    if recipe then
      local result = CC.ProfitOf(recipe)
      local _, sold = CC.SellOf(recipe.output)
      local row = { recipeID = id, name = recipe.name, recipe = recipe, result = result, sold = sold,
        unlearned = unlearned[id] == true }
      if groupOf(result) == "main" then
        if not row.unlearned or (type(result.profit) == "number" and result.missing == nil and result.profit > 0) then
          main[#main + 1] = row
        end
      elseif not row.unlearned then
        if unproven then
          row.thin = thinProfit(row)
          none[#none + 1] = row
        else
          hidden = hidden + 1
        end
      end
    end
  end
  local ranked, unpriced, unprofitable = GC.CraftMath.Rank(main)
  for _, row in ipairs(ranked) do row.group = "main" end
  table.sort(none, noneOrder)
  for _, row in ipairs(none) do
    row.group = "none"
    ranked[#ranked + 1] = row
  end
  return ranked, unpriced + hidden, unprofitable
end

--- The heading over a group of Worth crafting's rows; the first group has none.
function P.GroupTitle(group)
  if group == "none" then return GC.L["No estimate"] end
  return nil
end

--- How a no-estimate row reads (UI/CraftPanel.lua's paintRow): what its reagents cost, and what to
--- ask for one to cover them, with no profit. nil for the first group's.
function P.RowFace(data)
  if data.group ~= "none" then return nil end
  local result, lines = data.result, {}
  if type(result.cost) == "number" then
    lines[1] = GC.L["Reagents cost %s"]:format(Money(result.cost))
    local unit = GC.CraftMath.Breakeven(result.cost, data.recipe.per or 1)
    if unit then lines[2] = GC.L["Sell for at least %s each to break even."]:format(Money(unit)) end
  end
  return table.concat(lines, "\n"), "", nil
end

--- A row's tooltip, as UI/CraftPanel.lua's, with what its price rests on after it; for a recipe
--- whose item has no price, its reagents alone.
function P.RowTip(data)
  local result = type(data) == "table" and data.result or nil
  local lines
  if type(result) ~= "table" or type(result.profit) == "number" then
    lines = retailRowTip(data)
  elseif type(result.cost) == "number" then
    lines = retailRowTip({ recipe = data.recipe, result = result })
  else
    lines = {}
  end
  for _, line in ipairs(versionLines(result)) do lines[#lines + 1] = { line, "" } end
  return lines
end

--- The note under This recipe's figures: what the price rests on, nothing for the market's.
function P.CardNote(result)
  local lines = versionLines(result)
  return #lines > 0 and table.concat(lines, "\n") or nil
end

--- The strip's lines, and This recipe's for an item with no price: "No GoldCap price for ...", then
--- what is known of the version made, a line each.
function S.Lines(result)
  local lines = retailLines(result)
  if type(result) == "table" and result.missing and lines[1] then
    local text = { lines[1].text }
    for _, line in ipairs(versionLines(result)) do text[#text + 1] = line end
    lines[1].text = table.concat(text, "\n")
  end
  return lines
end
