local _, GC = ...

-- WoW: Forever's crafting panel. Loaded by GoldCap_Camelot.toc alone, after UI/CraftStrip.lua,
-- UI/CraftPanel.lua and UI/CraftQueueView.lua, whose fields it replaces where Forever's window or
-- data differ, the way Blizzard's own Forever files replace methods of a shared file
-- (Services/CraftClient_Camelot.lua says the same). Retail never loads it. The panel is retail's
-- panel otherwise: the same header, This recipe, Worth crafting and Queue.
--
-- - Where it stands: Forever's profession window hangs its book tab and a tab for each profession
--   off its right edge (Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml:
--   ProfessionsOverviewTab at the window's TOPRIGHT, the rest under it), each as wide as the
--   "common-sidetab" art (SidePanelTabButtonMixin.CalculateTabSizeBasedOnTabArt). The panel stands
--   right of them, or the player could not switch professions.
-- - The price line: Forever's prices are scans of its auction house, the player's own and every
--   player's through the Companion (Core/Data.lua's ForeverValueFor), never retail's region data,
--   so the line says which and how old.
-- - No strip under the reagents: Forever's form is narrower and keeps its Track Recipe checkbox
--   at its bottom right (Blizzard_Professions/Camelot/Blizzard_ProfessionsCrafting.lua's
--   OverrideArt), where the strip would end. This recipe shows the same three figures.
-- - A missing reagent price that a merchant visit can fill says so in This recipe, and so does one
--   a scan saw too few listed to price (Services/CraftClient_Camelot.lua's vendorHint and thin).
-- - Worth crafting in three groups (P.Rows): the recipes whose item has a proven price (its own
--   house's sales, or 20 listed without sales data), then those priced from the nearest markets'
--   sales ("Estimated from other markets", a loss among them last), then those with no estimate,
--   with what is known. The last two only for learned recipes, behind a switch beside "Unlearned
--   recipes too" that is on until the player turns it off (P.ShowsUnproven). Every row past the
--   first group, and This recipe, says what the price rests on and what a craft makes at today's
--   cheapest lot (CraftClient's `basis` and `scan`).
local P, S = GC.CraftPanel, GC.CraftStrip

-- How long prices count as fresh, as the Hoard's footer has it for the Companion's (two hours).
P.FRESH_SECONDS = 7200

--- Past the side tabs Forever's window hangs at its right edge; at the edge when it has none.
function P.Place(f, frame)
  local tab = type(frame) == "table" and frame.ProfessionsOverviewTab or nil
  local x = 0
  if type(tab) == "table" and type(tab.GetWidth) == "function" then
    local ok, width = pcall(tab.GetWidth, tab)
    if ok and type(width) == "number" and width > 0 then x = math.ceil(width) end
  end
  f:SetPoint("TOPLEFT", frame, "TOPRIGHT", x, 0)
end

local function ago(now, at)
  return GC.Util.FormatElapsedWords(math.max(0, now - at)) or GC.Util.FormatElapsedWords(0)
end

--- Where Forever's prices come from and how old they are, and whether the newest is fresh: the
--- player's own last scan of this auction house (GC.ForeverScan.Fold), every player's scans the
--- Companion brought (GC.Data.ForeverPayload), both, or neither.
function P.PricesNow(now)
  now = now or time()
  local F, D = GC.ForeverScan, GC.Data
  local fold = F and F.Fold and F.Fold() or nil
  local own = type(fold) == "table" and type(fold.at) == "number" and fold.at or nil
  local payload = D and D.ForeverPayload and D.ForeverPayload() or nil
  local crowd = type(payload) == "table" and type(payload.ts) == "number" and payload.ts or nil
  if not (own or crowd) then return GC.L["No scan of this auction house yet."], false end
  local newest = math.max(own or 0, crowd or 0)
  local fresh = now - newest < P.FRESH_SECONDS
  if own and crowd then
    return GC.L["Prices from your scan %s ago and the Companion %s ago"]:format(ago(now, own), ago(now, crowd)), fresh
  end
  if own then return GC.L["Prices from your scan %s ago"]:format(ago(now, own)), fresh end
  return GC.L["Prices from the Companion, %s ago"]:format(ago(now, crowd)), fresh
end

-- The strip is never built on Forever: its event frame asks for S.Attach a frame after the window
-- opens, and this one builds nothing.
function S.Attach() end

local retailLines = S.Lines
local retailRowTip = P.RowTip
local K = GC.Kit.Tokens.color
local Money = GC.Util.Money

local function breakevenSentence(cost, per)
  local unit = GC.CraftMath.Breakeven(cost, per)
  return unit and GC.L["Sell for at least %s each to break even."]:format(GC.Util.Money(unit)) or nil
end

local function signed(copper)
  return (copper > 0 and "+" or "") .. Money(copper)
end

-- The other faction's name, as the client spells it where it does: the market's own is the
-- character's (GC.ForeverScan._faction). nil while that is not known.
local function otherFaction()
  local mine = GC.ForeverScan and GC.ForeverScan._faction
  if mine == "Horde" then
    return type(_G.FACTION_ALLIANCE) == "string" and _G.FACTION_ALLIANCE or GC.L["Alliance"]
  elseif mine == "Alliance" then
    return type(_G.FACTION_HORDE) == "string" and _G.FACTION_HORDE or GC.L["Horde"]
  end
  return nil
end

-- "About 2g 80s from 7 sales: 1 here, 6 Alliance", a part with no sales left out.
local function pooledLine(b, unit)
  local own, sib, rest = b.own or 0, b.sib or 0, b.rest or 0
  local price, total, faction = Money(unit), own + sib + rest, otherFaction()
  if faction and own > 0 and rest > 0 then
    return GC.L["About %s from %d sales: %d here, %d %s, %d on other servers"]:format(price, total, own, sib, faction, rest)
  elseif faction and own > 0 then
    return GC.L["About %s from %d sales: %d here, %d %s"]:format(price, total, own, sib, faction)
  elseif faction and rest == 0 then
    return GC.L["About %s from %s's sales"]:format(price, faction)
  end
  return GC.L["About %s from %d sales on other servers"]:format(price, total)
end

-- What this house says of the item: what its few sales went for, or that it is listed and nothing
-- sold, or that nobody here lists it.
local function hereLine(b)
  if (b.own or 0) > 0 and b.ownMedian then return GC.L["%d here at %s"]:format(b.own, Money(b.ownMedian)) end
  if (b.own or 0) > 0 then return nil end
  if (b.listed or 0) > 0 then return GC.L["%d listed here, none sold this week"]:format(b.listed) end
  return GC.L["Not seen on your auction house"]
end

-- What one disenchant of the item gives on average, at the reagents' prices (nil: it is not
-- disenchanted, or nothing it gives has a price).
local function disenchantOf(itemID)
  local D, item = GC.ForeverDisenchant, _G.C_Item
  if not (D and type(item) == "table" and type(item.GetItemInfo) == "function") then return nil end
  local ok, _, _, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID = pcall(item.GetItemInfo, itemID)
  if not (ok and D.Can(itemID, quality, classID, equipLoc)) then return nil end
  return (D.Value(D.Results(quality, itemLevel, classID == 2), GC.CraftClient.UnitOf))
end

-- What the item is worth if it does not sell: a disenchant and a vendor's price.
local function floorLine(itemID)
  local F = GC.ForeverValue
  local vendor = type(itemID) == "number" and F and F.VendorUnit and F.VendorUnit(itemID) or nil
  if not vendor then return nil end
  local de = disenchantOf(itemID)
  if de then return GC.L["If it does not sell: disenchant about %s, vendor %s"]:format(Money(de), Money(vendor)) end
  return GC.L["If it does not sell: vendor %s"]:format(Money(vendor))
end

-- What a result's price rests on, a sentence each: nothing for a proven price.
local function basisLines(result)
  local b, out = result.basis, {}
  if type(b) ~= "table" then return out end
  local function add(line) if line then out[#out + 1] = line end end
  if b.kind == "pooled" then
    -- The markets' median, never the lot here that caps it.
    local e = GC.Data and GC.Data.ForeverPool and GC.Data.ForeverPool(result.output) or nil
    add(pooledLine(b, e and e.median or (GC.CraftClient.SellOf(result.output))))
    add(hereLine(b))
  elseif b.kind == "none" then
    add(hereLine(b))
    if b.sales and #b.sales > 0 then
      local each = {}
      for i, sale in ipairs(b.sales) do each[i] = Money(sale.copper) end
      add(GC.L["Sold %d times: %s"]:format(#b.sales, table.concat(each, ", ")))
    end
    if b.xregion then add(GC.L["Sells for %s in %s"]:format(Money(b.xregion.median), b.xregion.region:upper())) end
    add(floorLine(result.output))
  end
  return out
end

local function scanLine(result)
  local s = result.scan
  return s and GC.L["At today's cheapest lot %s: %s"]:format(Money(s.unit), signed(s.profit)) or nil
end

--- Whether Worth crafting lists learned recipes without a proven price too: the player's choice,
--- kept in the save, on until the player turns it off.
function P.ShowsUnproven()
  return type(GC.db) ~= "table" or GC.db.craftUnproven ~= false
end

--- The switch for P.ShowsUnproven, beside "Unlearned recipes too" in its style, or under it when
--- the two do not fit. Answers what the next line goes under and the height it adds.
function P.PaintSideSwitch(v, beside, LAYOUT)
  local b = v.unproven
  if not b then
    b = GC.Theme.Button(v, "ghost", "badge")
    b:SetGlow(false)
    b:SetHeight(LAYOUT.SEG_H)
    b:SetScript("OnClick", function()
      GC.db.craftUnproven = not P.ShowsUnproven()
      P.Refresh()
    end)
    GC.Theme.Parts.track(v, b.text)
    v.unproven = b
  end
  b:SetLabel(GC.L["Without a proven price too"])
  b:SetVariant(P.ShowsUnproven() and "active" or "ghost")
  local width = math.min(LAYOUT.INNER, math.ceil(P.ui.textWidth(b.text)) + 2 * LAYOUT.BUTTON_PAD)
  b:SetWidth(width)
  b:ClearAllPoints()
  if beside:GetWidth() + LAYOUT.GAP + width <= LAYOUT.INNER then
    b:SetPoint("LEFT", beside, "RIGHT", LAYOUT.GAP, 0)
    return beside, 0
  end
  b:SetPoint("TOPLEFT", beside, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  return b, LAYOUT.LINE_GAP + LAYOUT.SEG_H
end

--- The heading over a group of Worth crafting's rows; the first group has none.
function P.GroupTitle(group)
  if group == "estimate" then return GC.L["Estimated from other markets"] end
  if group == "none" then return GC.L["No estimate"] end
  return nil
end

-- Which group a recipe's result goes in: "estimate" priced from other markets, "none" its item
-- has no price, "main" otherwise (Core/CraftMath.lua's Rank counts what it cannot rank there).
local function groupOf(result)
  local b = type(result) == "table" and result.basis or nil
  if type(b) ~= "table" then return "main" end
  if b.kind == "none" or (b.kind == "listings" and b.thin) then return "none" end
  if b.kind == "pooled" and result.missing == nil then return "estimate" end
  return "main"
end

local function byName(a, b)
  local an, bn = tostring(a.name or ""), tostring(b.name or "")
  if an ~= bn then return an < bn end
  return (a.recipeID or 0) < (b.recipeID or 0)
end

-- The no-estimate order: any sale found first, then those listed here (by what a craft makes at
-- today's cheapest lot), then the rest, each by name.
local function tierOf(row)
  local b = row.result.basis
  if (b.own or 0) > 0 or (b.sib or 0) > 0 or (b.rest or 0) > 0 or (b.sales and #b.sales > 0) or b.xregion then
    return 1
  end
  return (b.listed or 0) > 0 and 2 or 3
end

local function noneOrder(a, b)
  local ta, tb = tierOf(a), tierOf(b)
  if ta ~= tb then return ta < tb end
  local pa, pb = a.result.scan and a.result.scan.profit, b.result.scan and b.result.scan.profit
  if ta == 2 and pa ~= pb then
    if pa == nil or pb == nil then return pb == nil end
    return pa > pb
  end
  return byName(a, b)
end

local function estimateOrder(a, b)
  if a.result.profit ~= b.result.profit then return a.result.profit > b.result.profit end
  return byName(a, b)
end

--- Worth crafting's rows, each with its `group`: "main" the recipes a proven price says make a
--- profit, by profit per craft; then, with P.ShowsUnproven and for learned recipes alone,
--- "estimate" those priced from other markets by profit (a loss last), and "none" those whose item
--- has no price. Answers them with how many have no price and how many make no profit, as on
--- retail: a learned recipe the switch hides counts as having no price. A recipe not learned is
--- listed in the first group for its profit alone, and counted nowhere.
function P.Rows()
  local CC = GC.CraftClient
  local unproven = P.ShowsUnproven()
  local main, groups, hidden = {}, { estimate = {}, none = {} }, 0
  local ids, unlearned = CC.KnownRecipes(P.ShowsUnlearned())
  for _, id in ipairs(ids) do
    local recipe = CC.Snapshot(id)
    if recipe then
      local _, sold = CC.SellOf(recipe.output)
      local result = CC.ProfitOf(recipe)
      local row = { recipeID = id, name = recipe.name, recipe = recipe, result = result, sold = sold,
        unlearned = unlearned[id] == true }
      local group = groupOf(result)
      if group == "main" then
        if not row.unlearned or (type(result) == "table" and type(result.profit) == "number"
            and result.missing == nil and result.profit > 0) then
          main[#main + 1] = row
        end
      elseif not row.unlearned then
        if unproven then
          local list = groups[group]
          list[#list + 1] = row
        else
          hidden = hidden + 1
        end
      end
    end
  end
  local ranked, unpriced, unprofitable = GC.CraftMath.Rank(main)
  for _, row in ipairs(ranked) do row.group = "main" end
  table.sort(groups.estimate, estimateOrder)
  table.sort(groups.none, noneOrder)
  for _, group in ipairs({ "estimate", "none" }) do
    for _, row in ipairs(groups[group]) do
      row.group = group
      ranked[#ranked + 1] = row
    end
  end
  return ranked, unpriced + hidden, unprofitable
end

--- How a row past the first group reads (UI/CraftPanel.lua's paintRow): its math line with what
--- the price rests on and what a craft makes at today's cheapest lot under it, and its profit,
--- "about" for an estimate and none for a recipe with no estimate. nil for the first group's.
function P.RowFace(data)
  local result = data.result
  if data.group ~= "estimate" and data.group ~= "none" then return nil end
  local lines = {}
  local profit, tone = "", nil
  if data.group == "estimate" then
    lines[1] = P.ui.mathLine(data.recipe, result)
    if result.profit > 0 then
      profit, tone = GC.L["about +%s"]:format(Money(result.profit)), K.profit
    else
      profit, tone = Money(result.profit), K.loss
    end
  elseif type(result.cost) == "number" then
    lines[1] = GC.L["Reagents cost %s"]:format(Money(result.cost))
    lines[2] = breakevenSentence(result.cost, data.recipe.per or 1)
  end
  for _, line in ipairs(basisLines(result)) do lines[#lines + 1] = line end
  lines[#lines + 1] = scanLine(result)
  return table.concat(lines, "\n"), profit, tone
end

--- A row's tooltip, as on retail; for a recipe whose item has no price, its reagents alone.
function P.RowTip(data)
  local result = type(data) == "table" and data.result or nil
  if type(result) ~= "table" or type(result.profit) == "number" then return retailRowTip(data) end
  if type(result.cost) ~= "number" then return {} end
  return retailRowTip({ recipe = data.recipe, result = result })
end

--- The note under a priced card's cells: what to ask for one to cover its reagents, what an
--- estimate rests on, and what a craft makes at today's cheapest lot.
function P.CardNote(result, recipe)
  if type(result) ~= "table" then return nil end
  local lines = { breakevenSentence(result.cost, type(recipe) == "table" and recipe.per or 1) }
  for _, line in ipairs(basisLines(result)) do lines[#lines + 1] = line end
  lines[#lines + 1] = scanLine(result)
  return #lines > 0 and table.concat(lines, " ") or nil
end

--- The strip's lines, as This recipe shows the first: "No GoldCap price for ...", and on Forever how
--- a merchant gives a vendor's reagent its price, how many listed an auction house price needs,
--- what the item's price would rest on and what a craft makes at today's cheapest lot. A priced
--- estimate gets a line saying what it rests on.
function S.Lines(result)
  local lines = retailLines(result)
  if type(result) ~= "table" or not lines[1] then return lines end
  if not result.missing then
    local notes = basisLines(result)
    if #notes > 0 then lines[#lines + 1] = { text = table.concat(notes, " "), color = GC.Theme.color.fg } end
    return lines
  end
  local text = { lines[1].text }
  if result.vendorHint then text[#text + 1] = GC.L["A reagent a vendor sells gets its price once you open that vendor."] end
  if result.thin then
    text[#text + 1] = GC.L["An auction house price needs at least %d listed."]:format(GC.ForeverDeals.C.MARKET_MIN_UNITS)
  end
  if result.cost and result.per then text[#text + 1] = breakevenSentence(result.cost, result.per) end
  for _, line in ipairs(basisLines(result)) do text[#text + 1] = line end
  text[#text + 1] = scanLine(result)
  lines[1].text = table.concat(text, " ")
  return lines
end
