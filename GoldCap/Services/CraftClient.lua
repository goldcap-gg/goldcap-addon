local _, GC = ...

-- The one reader of the retail profession window for GoldCap's crafting: recipe snapshots, the
-- character's known recipes, the open recipe's reagents as the player allocated them, prices,
-- counts and owned auctions. Everything the crafting panel and strip know about the client comes
-- through here; Core/CraftMath.lua and Core/CraftQueue.lua stay pure.
--
-- Read-only. Nothing here crafts, buys or changes Blizzard's frames: the form and its transaction
-- are read through the methods Blizzard's own code reads them with
-- (ProfessionsRecipeSchematicFormMixin, ProfessionsRecipeTransactionMixin), every read under pcall,
-- and any failure is "nothing to show", never an error in the player's face.
--
-- Every API here is in Blizzard's source for live 12.1.5 (wowsrc.py): the documented
-- C_TradeSkillUI reads, and GetFilteredRecipeIDs, IsTradeSkillGuild, IsTradeSkillGuildMember and
-- IsTradeSkillLinked, which Blizzard_Professions calls undocumented. GetAllRecipeIDs is only on the
-- wiki: it is asked for only when GetFilteredRecipeIDs is not there.
GC.CraftClient = GC.CraftClient or {}
local CC = GC.CraftClient

-- Enum values from TradeSkillUITypesDocumentation.lua and ProfessionConstantsDocumentation.lua,
-- read from the client's Enum when it carries them.
local function enum(group, name, fallback)
  local e = _G.Enum
  local g = type(e) == "table" and e[group] or nil
  local v = type(g) == "table" and g[name] or nil
  return type(v) == "number" and v or fallback
end

-- Snapshots of this session, by recipe id: a recipe's slots do not change while the game runs.
-- A refusal is remembered too (false), but only when the client answered: a recipe the client
-- has not loaded yet is asked again next time.
local snapshots = {}

local function ts() return _G.C_TradeSkillUI end

local function call(name, ...)
  local api = ts()
  local fn = type(api) == "table" and api[name] or nil
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function refuses(info, schematic)
  return schematic.recipeType ~= enum("TradeskillRecipeType", "Item", 1)
    or info.isRecraft == true or info.isSalvageRecipe == true or info.isEnchantingRecipe == true
    or info.isGatheringRecipe == true or info.isDummyRecipe == true
    or type(schematic.outputItemID) ~= "number"
end

-- The slots a craft cannot do without: required Basic reagents and required Modifying ones (a
-- spark). Finishing and Automatic reagents, optional slots and slots the form hides are left out.
-- nil when one of them has a reagent that needs a count of its own (variableQuantities,
-- ProfessionsUtil's GetQuantityRequired): every count here is the slot's quantityRequired.
local function slotsOf(schematic)
  local basic, modifying = enum("CraftingReagentType", "Basic", 1), enum("CraftingReagentType", "Modifying", 0)
  local slots = {}
  for _, s in ipairs(type(schematic.reagentSlotSchematics) == "table" and schematic.reagentSlotSchematics or {}) do
    if type(s) == "table" and s.required == true and s.hiddenInCraftingForm ~= true
        and (s.reagentType == basic or s.reagentType == modifying) and type(s.quantityRequired) == "number" then
      if type(s.variableQuantities) == "table" and #s.variableQuantities > 0 then return nil end
      local ids, currency = {}, nil
      for _, r in ipairs(type(s.reagents) == "table" and s.reagents or {}) do
        if type(r) == "table" and type(r.itemID) == "number" then
          ids[#ids + 1] = r.itemID
        elseif type(r) == "table" and type(r.currencyID) == "number" then
          currency = currency or r.currencyID
        end
      end
      if #ids > 0 then
        slots[#slots + 1] = { slotIndex = s.slotIndex, q = s.quantityRequired, ids = ids }
      elseif currency then
        slots[#slots + 1] = { slotIndex = s.slotIndex, q = s.quantityRequired, currency = currency }
      end
    end
  end
  return slots
end

--- A recipe as GoldCap prices it ({ recipeID, name, per, output, outputs, slots }), or nil for a
--- recipe that makes no item to sell (salvage, recraft, enchant, gathering, a dummy, no output) or
--- one whose required reagent needs a count of its own.
function CC.Snapshot(recipeID)
  if type(recipeID) ~= "number" then return nil end
  local known = snapshots[recipeID]
  if known ~= nil then return known or nil end
  local okI, info = call("GetRecipeInfo", recipeID)
  local okS, schematic = call("GetRecipeSchematic", recipeID, false)
  if not (okI and okS and type(info) == "table" and type(schematic) == "table") then return nil end
  local slots = not refuses(info, schematic) and slotsOf(schematic) or nil
  if not slots then
    snapshots[recipeID] = false
    return nil
  end
  local outputs = {}
  local set = GC.CraftCapture and GC.CraftCapture.OutputIDs
    and GC.CraftCapture.OutputIDs(ts(), recipeID, schematic.outputItemID) or { [schematic.outputItemID] = true }
  for id in pairs(set) do outputs[#outputs + 1] = id end
  table.sort(outputs)
  local recipe = {
    recipeID = recipeID,
    name = info.name or schematic.name or tostring(recipeID),
    per = math.max(1, tonumber(schematic.quantityMin) or 1),
    output = schematic.outputItemID,
    outputs = outputs,
    slots = slots,
  }
  snapshots[recipeID] = recipe
  return recipe
end

--- The recipes this character has learned in the profession the window shows, as the window
--- lists them (the player's search and filters included), that GoldCap can price.
function CC.KnownRecipes()
  local api = ts()
  if type(api) ~= "table" then return {} end
  local ok, ids
  if type(api.GetFilteredRecipeIDs) == "function" then
    ok, ids = pcall(api.GetFilteredRecipeIDs)
  elseif type(api.GetAllRecipeIDs) == "function" then
    ok, ids = pcall(api.GetAllRecipeIDs)
  end
  if not ok or type(ids) ~= "table" then return {} end
  local okP, prof = call("GetChildProfessionInfo")
  local skillLine = okP and type(prof) == "table" and prof.professionID or nil
  if type(skillLine) ~= "number" then return {} end
  local out = {}
  for _, id in ipairs(ids) do
    local okL, inLine = call("IsRecipeInSkillLine", id, skillLine)
    local okR, info = call("GetRecipeInfo", id)
    if okL and inLine == true and okR and type(info) == "table" and info.learned == true and CC.Snapshot(id) then
      out[#out + 1] = id
    end
  end
  return out
end

--- The crafting page's recipe form, or nil before Blizzard_Professions has loaded.
function CC.Form()
  local frame = _G.ProfessionsFrame
  local page = type(frame) == "table" and frame.CraftingPage or nil
  local form = type(page) == "table" and page.SchematicForm or nil
  return type(form) == "table" and form or nil
end

--- What the window shows for the selected recipe: { recipeID, level, output, alloc, learned },
--- alloc the reagents allocated per slot ({ { itemID, q }, ... }, a slot with nothing allocated
--- absent), output the item the window says this allocation makes, learned true only when the
--- character knows the recipe (Blizzard's list shows unlearned recipes too). nil when the recipes
--- page is not on screen, or a recraft is open.
function CC.OpenRecipe()
  local form = CC.Form()
  if not form then return nil end
  local ok, open = pcall(function()
    if not form:IsVisible() then return nil end
    local info = form:GetRecipeInfo()
    if type(info) ~= "table" or type(info.recipeID) ~= "number" or info.isRecraft == true then return nil end
    local tx = form:GetTransaction()
    if type(tx) ~= "table" then return nil end
    -- Recrafting an item opens its normal recipe (info.isRecraft false) with a recraft
    -- transaction, whose slots and output are the recraft's: the transaction says which it is
    -- (ProfessionsRecipeTransactionMixin:IsRecraft, Blizzard_ProfessionsTransaction.lua).
    if tx:IsRecraft() then return nil end
    local alloc = {}
    for _, tbl in tx:Enumerate() do
      local slot = type(tbl) == "table" and tbl.reagentSlotSchematic or nil
      local list = {}
      if type(tbl) == "table" and type(tbl.allocations) == "table" then
        for _, a in tbl.allocations:Enumerate() do
          local reagent, q = a:GetReagent(), a:GetQuantity()
          if type(reagent) == "table" and type(reagent.itemID) == "number" and type(q) == "number" and q > 0 then
            list[#list + 1] = { itemID = reagent.itemID, q = q }
          end
        end
      end
      if type(slot) == "table" and type(slot.slotIndex) == "number" and #list > 0 then alloc[slot.slotIndex] = list end
    end
    local data = ts().GetRecipeOutputItemData(info.recipeID, tx:CreateCraftingReagentInfoTbl(), tx:GetAllocationItemGUID())
    return { recipeID = info.recipeID, level = form:GetCurrentRecipeLevel(),
      output = type(data) == "table" and data.itemID or nil, alloc = alloc, learned = info.learned == true }
  end)
  return ok and open or nil
end

--- What a vendor charges for one of an item, as a BUY list the player holds says (nil: none does).
function CC.VendorOf(itemID)
  if type(itemID) ~= "number" then return nil end
  local vendor = GC.AppRuns and GC.AppRuns.VendorUnitFor and GC.AppRuns.VendorUnitFor(itemID) or nil
  return type(vendor) == "number" and vendor or nil
end

--- What one of a reagent costs: the vendor price a BUY list carries for it, else the market price
--- GoldCap trusts for a cost (the order Core/Init.lua's craft capture prices a reagent in).
function CC.UnitOf(itemID)
  if type(itemID) ~= "number" then return nil end
  local vendor = CC.VendorOf(itemID)
  if vendor then return vendor end
  local v = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(itemID) or nil
  local unit = GC.Tooltip.TrustedHeadline(v)
  return type(unit) == "number" and math.floor(unit) or nil
end

--- What one of a crafted item sells for on the market, and how many sell a day (nil: unknown).
function CC.SellOf(itemID)
  if type(itemID) ~= "number" then return nil end
  local v = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(itemID) or nil
  local unit = GC.Tooltip.TrustedHeadline(v)
  if type(unit) ~= "number" then return nil end
  return math.floor(unit), type(v) == "table" and type(v.sold) == "number" and v.sold or nil
end

--- Core/CraftMath.lua's Profit at these prices. `open` counts only when it is this recipe's.
function CC.ProfitOf(recipe, open)
  if type(open) == "table" and type(recipe) == "table" and open.recipeID ~= nil and open.recipeID ~= recipe.recipeID then
    open = nil
  end
  return GC.CraftMath.Profit(recipe, CC.UnitOf, function(id) return (CC.SellOf(id)) end, open)
end

--- How many of an item the character holds in bags, bank, reagent bank and warband bank together:
--- the count the BUY tab buys against (UI/BuyFrame.lua) and crafting pulls from.
function CC.CountOf(itemID)
  local item = _G.C_Item
  local fn = type(item) == "table" and item.GetItemCount or nil
  if type(fn) ~= "function" or type(itemID) ~= "number" then return 0 end
  local ok, n = pcall(fn, itemID, true, false, true, true)
  return ok and type(n) == "number" and n or 0
end

--- How much of a currency the character holds (0 when the client does not know it): the count
--- Blizzard's own form reads for a currency reagent (ProfessionsUtil.GetReagentQuantityInPossession).
function CC.CurrencyCount(currencyID)
  local ci = _G.C_CurrencyInfo
  local fn = type(ci) == "table" and ci.GetCurrencyInfo or nil
  if type(fn) ~= "function" or type(currencyID) ~= "number" then return 0 end
  local ok, info = pcall(fn, currencyID)
  local n = ok and type(info) == "table" and info.quantity or nil
  return type(n) == "number" and n or 0
end

--- How many crafts of a recipe the character's reagents allow (0 when the client cannot say).
function CC.Craftable(recipeID, level)
  local ok, n = call("GetCraftableCount", recipeID, level)
  return ok and type(n) == "number" and n or 0
end

--- A reagent or crafted item by name, for a sentence: { itemID } or { currencyID }.
function CC.MissingName(m)
  if type(m) ~= "table" then return "" end
  if type(m.currencyID) == "number" then
    local ci = _G.C_CurrencyInfo
    local ok, info = false, nil
    if type(ci) == "table" and type(ci.GetCurrencyInfo) == "function" then ok, info = pcall(ci.GetCurrencyInfo, m.currencyID) end
    if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
    return GC.L["Currency %d"]:format(m.currencyID)
  end
  local item = _G.C_Item
  local ok, name = false, nil
  if type(item) == "table" and type(item.GetItemNameByID) == "function" then ok, name = pcall(item.GetItemNameByID, m.itemID) end
  if ok and type(name) == "string" and name ~= "" then return name end
  return GC.L["Item %d"]:format(tonumber(m.itemID) or 0)
end

-- Blizzard's Professions.IsViewingExternalCraftingList (a guild's, a guild member's or a linked
-- list) plus an NPC's crafting and runeforging: none of these is the character's own to craft from.
local EXTERNAL = { "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsTradeSkillLinked", "IsNPCCrafting", "IsRuneforging" }

--- True when the window lists the character's own recipes. A function the client lacks counts
--- as not external.
function CC.IsOwnList()
  local api = ts()
  if type(api) ~= "table" then return false end
  for _, name in ipairs(EXTERNAL) do
    local fn = api[name]
    if type(fn) == "function" then
      local ok, yes = pcall(fn)
      if ok and yes == true then return false end
    end
  end
  return true
end

--- "Name-Realm" of the character at the keyboard, or nil.
function CC.Char()
  local ctx = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
  local char = type(ctx) == "table" and ctx.char or nil
  return type(char) == "string" and char ~= "" and char or nil
end

--- Reads the character's own auctions into the craft store's listed counts. False when there is
--- no character or the read failed.
function CC.ReadListed()
  local char = CC.Char()
  if not char then return false end
  local ok = pcall(function()
    GC.CraftQueue.FoldListed(char, _G.C_AuctionHouse.GetOwnedAuctions(), time())
  end)
  return ok
end
