-- API-shaped doubles of the retail profession window, for the crafting specs: C_TradeSkillUI, the
-- crafting page's SchematicForm and its transaction, EventRegistry, and the item, currency and
-- auction reads crafting makes. Every name here is one the client has, checked against Blizzard's
-- own source (wowsrc.py, live 12.1.5): the documented C_TradeSkillUI functions, and the
-- undocumented ones Blizzard_Professions calls (GetFilteredRecipeIDs, IsTradeSkillGuild,
-- IsTradeSkillGuildMember, IsTradeSkillLinked). The form's methods are
-- ProfessionsRecipeSchematicFormMixin's, the transaction's ProfessionsRecipeTransactionMixin's, an
-- allocation's AllocationMixin's (Blizzard_ProfessionsTransaction.lua).
--
-- Strict: a name the double does not carry raises, so production code cannot come to lean on one
-- the client does not have. `opts.absent` lists names to answer nil instead, for a client that
-- lacks a function; GetAllRecipeIDs (on the wiki, nowhere in Blizzard's code) exists only when
-- `opts.all` hands its answer.
--
--   TS.install(opts) -> restore
--   opts = {
--     recipes = { [recipeID] = { info = TradeSkillRecipeInfo, schematic = CraftingRecipeSchematic,
--       inSkillLine = bool (default true), craftable = n, quality = { itemID, ... } } },
--     filtered = { recipeID, ... }, all = { recipeID, ... } | nil, professionID = n,
--     open = { recipeID, level, allocations = { [slotIndex] = { { itemID, q }, ... } }, output, guid,
--       recraft = bool (the transaction's IsRecraft) } | nil,
--     counts = { [itemID] = n }, names = { [itemID] = name }, currencies = { [currencyID] = name },
--     owned = { OwnedAuctionInfo, ... },
--     external = { guild, guildMember, linked, npc, runeforging },
--     absent = { [name] = true },
--   }
--   TS.trigger(eventName, ...) runs every EventRegistry callback registered for it.
--   TS.calls: every call made, { name, args = { ... } }, in order; TS.callsOf(name) filters them.
local W = require("spec.support.wow_frames")

local TS = { calls = {} }

local GLOBALS = { "C_TradeSkillUI", "ProfessionsFrame", "EventRegistry", "C_Item", "C_CurrencyInfo",
  "C_AuctionHouse", "Enum", "C_Timer", "GetCoinTextureString" }

local function strict(label, t, absent)
  return setmetatable(t, { __index = function(_, key)
    if absent and absent[key] then return nil end
    error(("%s.%s: the client has no such name"):format(label, tostring(key)), 2)
  end })
end

local function record(name, ...)
  TS.calls[#TS.calls + 1] = { name = name, args = { ... }, n = select("#", ...) }
end

function TS.callsOf(name)
  local out = {}
  for _, c in ipairs(TS.calls) do if c.name == name then out[#out + 1] = c end end
  return out
end

-- CreateTableEnumerator's shape: for index, value in enumerator do.
local function enumerate(list)
  local function step(t, i)
    i = i + 1
    local v = t[i]
    if v ~= nil then return i, v end
  end
  return step, list, 0
end

local function allocationOf(itemID, quantity)
  local a = {}
  function a:GetReagent() return { itemID = itemID } end
  function a:GetQuantity() return quantity end
  return a
end

local function transactionFor(schematic, open)
  local tbls = {}
  for i, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
    local allocs = {}
    for _, a in ipairs(open.allocations and open.allocations[slot.slotIndex] or {}) do
      allocs[#allocs + 1] = allocationOf(a.itemID, a.q)
    end
    local allocations = {}
    function allocations:Enumerate() return enumerate(allocs) end
    tbls[i] = { reagentSlotSchematic = slot, allocations = allocations }
  end
  local tx = {}
  TS.reagentInfoTbl = { "reagent info for " .. tostring(open.recipeID) }
  function tx:Enumerate() return enumerate(tbls) end
  function tx:CreateCraftingReagentInfoTbl() record("CreateCraftingReagentInfoTbl"); return TS.reagentInfoTbl end
  function tx:GetAllocationItemGUID() return open.guid end
  -- ProfessionsRecipeTransactionMixin:IsRecraft answers the transaction's own flag, which the form
  -- sets when an item is recrafted (Professions.SetRecraftingTransitionData). The recipe info the
  -- form holds then is the item's normal recipe, isRecraft false
  -- (Blizzard_ProfessionsRecipeSchematicForm.lua, Init).
  function tx:IsRecraft() return open.recraft == true end
  return strict("transaction", tx)
end

function TS.install(opts)
  opts = opts or {}
  TS.calls = {}
  TS.callbacks = {}
  TS.opts = opts
  local saved = {}
  for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
  local restoreFrames = W.install()
  local absent = opts.absent or {}
  local recipes = opts.recipes or {}

  local api = {
    GetRecipeSchematic = function(id, isRecraft)
      record("GetRecipeSchematic", id, isRecraft)
      return recipes[id] and recipes[id].schematic or nil
    end,
    GetRecipeInfo = function(id)
      record("GetRecipeInfo", id)
      return recipes[id] and recipes[id].info or nil
    end,
    GetFilteredRecipeIDs = function() record("GetFilteredRecipeIDs"); return opts.filtered or {} end,
    IsRecipeInSkillLine = function(id, skillLineID)
      record("IsRecipeInSkillLine", id, skillLineID)
      local r = recipes[id]
      return r ~= nil and r.inSkillLine ~= false and skillLineID == opts.professionID
    end,
    GetChildProfessionInfo = function() return { professionID = opts.professionID or 0 } end,
    GetRecipeOutputItemData = function(id, reagents, guid, qualityID)
      record("GetRecipeOutputItemData", id, reagents, guid, qualityID)
      local r = recipes[id]
      if qualityID then
        local byQuality = r and r.qualityOutputs or {}
        return byQuality[qualityID] and { itemID = byQuality[qualityID] } or nil
      end
      if opts.open and opts.open.recipeID == id and opts.open.output then return { itemID = opts.open.output } end
      return r and r.schematic and { itemID = r.schematic.outputItemID } or nil
    end,
    GetRecipeQualityItemIDs = function(id) return recipes[id] and recipes[id].quality or nil end,
    GetCraftableCount = function(id, level)
      record("GetCraftableCount", id, level)
      return recipes[id] and recipes[id].craftable or 0
    end,
    CraftRecipe = function(...) record("CraftRecipe", ...) end,
    IsTradeSkillGuild = function() return (opts.external or {}).guild == true end,
    IsTradeSkillGuildMember = function() return (opts.external or {}).guildMember == true end,
    IsTradeSkillLinked = function() return (opts.external or {}).linked == true, nil end,
    IsNPCCrafting = function() return (opts.external or {}).npc == true end,
    IsRuneforging = function() return (opts.external or {}).runeforging == true end,
  }
  if opts.all then api.GetAllRecipeIDs = function() record("GetAllRecipeIDs"); return opts.all end end
  for name in pairs(absent) do api[name] = nil end
  _G.C_TradeSkillUI = strict("C_TradeSkillUI", api, absent)

  -- The window: ProfessionsFrame > CraftingPage > SchematicForm, with the form's reagent blocks
  -- (parentKey Reagents and OptionalReagents, Blizzard_ProfessionsRecipeSchematicForm.xml) and its
  -- extraSlotFrames array (recraft, salvage and enchant slots, hidden unless that kind is open).
  local frame = W.CreateFrame("Frame", nil, nil)
  frame:SetSize(942, 658)
  local page = W.CreateFrame("Frame", nil, frame)
  local form = W.CreateFrame("Frame", nil, page)
  form.Reagents = W.CreateFrame("Frame", nil, form)
  form.OptionalReagents = W.CreateFrame("Frame", nil, form)
  local recraft = W.CreateFrame("Frame", nil, form)
  recraft:Hide()
  form.extraSlotFrames = { recraft }
  local open = opts.open
  function form:GetRecipeInfo()
    return open and recipes[open.recipeID] and recipes[open.recipeID].info or nil
  end
  function form:GetTransaction()
    if not open then return nil end
    return transactionFor(recipes[open.recipeID] and recipes[open.recipeID].schematic, open)
  end
  function form:GetCurrentRecipeLevel() return open and open.level or nil end
  if not open then form:Hide() end
  page.SchematicForm = form
  page.RecipeList = W.CreateFrame("Frame", nil, page)
  frame.CraftingPage = page
  _G.ProfessionsFrame = frame
  TS.frame, TS.page, TS.form = frame, page, form

  _G.EventRegistry = strict("EventRegistry", {
    RegisterCallback = function(_, event, func, owner)
      record("RegisterCallback", event, owner)
      TS.callbacks[event] = TS.callbacks[event] or {}
      TS.callbacks[event][owner or func] = func
      return owner
    end,
    UnregisterCallback = function(_, event, owner)
      if TS.callbacks[event] then TS.callbacks[event][owner] = nil end
    end,
  })

  _G.C_Item = strict("C_Item", {
    GetItemCount = function(id, includeBank, includeUses, includeReagentBank, includeAccountBank)
      record("GetItemCount", id, includeBank, includeUses, includeReagentBank, includeAccountBank)
      return (opts.counts or {})[id] or 0
    end,
    GetItemNameByID = function(id) return (opts.names or {})[id] end,
  })
  _G.C_CurrencyInfo = strict("C_CurrencyInfo", {
    GetCurrencyInfo = function(id)
      local name = (opts.currencies or {})[id]
      return name and { name = name, currencyID = id } or nil
    end,
    GetCoinTextureString = function(copper) return tostring(copper) .. "c" end,
  })
  _G.C_AuctionHouse = strict("C_AuctionHouse", {
    GetOwnedAuctions = function() record("GetOwnedAuctions"); return opts.owned or {} end,
  })
  -- C_Timer.After(0, fn) runs fn on the next frame: here, when the spec says (TS.runTimers).
  TS.timers = {}
  _G.C_Timer = strict("C_Timer", { After = function(_, fn) TS.timers[#TS.timers + 1] = fn end })
  _G.GetCoinTextureString = function(copper) return tostring(copper) .. "c" end
  _G.Enum = {
    TradeskillRecipeType = { Item = 1, Salvage = 2, Enchant = 3, Gathering = 4 },
    CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 },
    AuctionStatus = { Active = 0, Sold = 1 },
  }

  return function()
    restoreFrames()
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
  end
end

--- Runs the timers queued so far (one frame passing), and any they queue in turn.
function TS.runTimers()
  local guard = 0
  while #TS.timers > 0 do
    local due = TS.timers
    TS.timers = {}
    for _, fn in ipairs(due) do fn() end
    guard = guard + 1
    assert(guard < 50, "timers keep queueing timers")
  end
end

--- GoldCap as the client loads it for crafting: prices, the craft modules and the kit, in TOC order.
function TS.craftGC()
  local helper = require("spec.spec_helper")
  local GC = helper.loadModule("Core/Util.lua")
  for _, path in ipairs({ "Core/Trigger.lua", "Core/CraftCapture.lua", "Core/CraftMath.lua", "Core/CraftQueue.lua",
    "Services/CraftClient.lua", "UI/Theme.lua", "UI/Tooltip.lua" }) do
    helper.loadModule(path, GC)
  end
  return GC
end

function TS.trigger(event, ...)
  for owner, func in pairs(TS.callbacks[event] or {}) do func(owner, ...) end
end

-- Builders for the documented shapes (TradeSkillUITypesDocumentation.lua).
function TS.info(recipeID, name, extra)
  local info = { recipeID = recipeID, name = name, learned = true, isRecraft = false, isSalvageRecipe = false,
    isEnchantingRecipe = false, isGatheringRecipe = false, isDummyRecipe = false }
  for k, v in pairs(extra or {}) do info[k] = v end
  return info
end

function TS.slot(slotIndex, quantityRequired, reagents, extra)
  local s = { slotIndex = slotIndex, quantityRequired = quantityRequired, reagents = reagents,
    reagentType = 1, required = true, hiddenInCraftingForm = false, dataSlotIndex = slotIndex }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

function TS.items(...)
  local out = {}
  for i, id in ipairs({ ... }) do out[i] = { itemID = id } end
  return out
end

function TS.schematic(recipeID, outputItemID, slots, extra)
  local s = { recipeID = recipeID, name = "Recipe " .. recipeID, recipeType = 1, quantityMin = 1, quantityMax = 1,
    outputItemID = outputItemID, reagentSlotSchematics = slots or {}, isRecraft = false }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

return TS
