local helper = require("spec.spec_helper")
local TS = require("spec.support.trade_skill")

-- Services/CraftClient.lua: the one reader of the profession window. Recipes become snapshots,
-- the open recipe's allocation and crafted item are read as the window shows them, and prices,
-- counts and owned auctions come from where the rest of GoldCap reads them.
describe("craft client", function()
  local GC, CC, restore, VALUES, VENDOR

  local function commodity(mv, sold)
    return { mv = mv, sold = sold, ts = 0, source = "import", kind = "region_commodity" }
  end

  -- Recipe 7: a Basic slot of three qualities, a required spark, an optional slot, a finishing
  -- slot and a hidden one; it makes two of item 900 (901 at the higher quality).
  local function potion(extraInfo, extraSchematic)
    return {
      info = TS.info(7, "Potion", extraInfo),
      schematic = TS.schematic(7, 900, {
        TS.slot(1, 3, TS.items(101, 102, 103)),
        TS.slot(2, 1, TS.items(300), { reagentType = 0 }),
        TS.slot(3, 1, TS.items(400), { reagentType = 0, required = false }),
        TS.slot(4, 1, TS.items(500), { reagentType = 2, required = false }),
        TS.slot(5, 1, TS.items(600), { hiddenInCraftingForm = true }),
      }, extraSchematic or { quantityMin = 2, quantityMax = 2 }),
      quality = { 901, 900 },
    }
  end

  local function load(opts)
    restore = TS.install(opts)
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("UI/Tooltip.lua", GC)
    helper.loadModule("Core/CraftCapture.lua", GC)
    helper.loadModule("Core/CraftMath.lua", GC)
    helper.loadModule("Core/CraftQueue.lua", GC)
    helper.loadModule("Services/CraftClient.lua", GC)
    VALUES, VENDOR = {}, {}
    GC.Data = { GetItemValue = function(id) return VALUES[id] end }
    GC.AppRuns = { VendorUnitFor = function(id) return VENDOR[id] end }
    GC.Ledger = { Context = function() return { char = "Name-Realm", region = "eu" } end }
    GC.db = {}
    CC = GC.CraftClient
  end

  after_each(function() if restore then restore() end end)

  it("snapshots the required slots in schematic order, lowest quality first", function()
    load({ recipes = { [7] = potion() } })
    assert.same({
      recipeID = 7, name = "Potion", per = 2, output = 900, outputs = { 900, 901 },
      slots = { { slotIndex = 1, q = 3, ids = { 101, 102, 103 } }, { slotIndex = 2, q = 1, ids = { 300 } } },
    }, CC.Snapshot(7))
    -- One read per recipe for the session.
    CC.Snapshot(7)
    assert.equal(1, #TS.callsOf("GetRecipeSchematic"))
    assert.same({ 7, false }, TS.callsOf("GetRecipeSchematic")[1].args)
  end)

  describe("refuses recipes GoldCap does not price", function()
    local cases = {
      { "salvage", { isSalvageRecipe = true } },
      { "recraft", { isRecraft = true } },
      { "enchant", { isEnchantingRecipe = true } },
      { "gathering", { isGatheringRecipe = true } },
      { "dummy", { isDummyRecipe = true } },
      { "recipeType 2", nil, { recipeType = 2 } },
      { "no output", nil, { outputItemID = false } },
    }
    for _, c in ipairs(cases) do
      it(c[1], function()
        local r = potion(c[2], c[3])
        if r.schematic.outputItemID == false then r.schematic.outputItemID = nil end
        load({ recipes = { [7] = r } })
        assert.is_nil(CC.Snapshot(7))
      end)
    end
  end)

  it("gives nothing for a recipe the client does not answer for", function()
    load({ recipes = {} })
    assert.is_nil(CC.Snapshot(99))
    assert.is_nil(CC.Snapshot("7"))
  end)

  it("takes a currency reagent as a currency slot", function()
    local r = potion()
    r.schematic.reagentSlotSchematics = { TS.slot(1, 2, TS.items(101)), TS.slot(2, 5, { { currencyID = 3008 } }) }
    load({ recipes = { [7] = r } })
    assert.same({ { slotIndex = 1, q = 2, ids = { 101 } }, { slotIndex = 2, q = 5, currency = 3008 } },
      CC.Snapshot(7).slots)
  end)

  it("lists the learned recipes of the open profession that the window lists", function()
    local two, three = potion(), potion()
    two.info = TS.info(2, "Two", { learned = false })
    three.inSkillLine = false
    load({ recipes = { [1] = potion(), [2] = two, [3] = three }, filtered = { 1, 2, 3 }, professionID = 2823 })
    assert.same({ 1 }, CC.KnownRecipes())
    assert.same({ 1, 2823 }, TS.callsOf("IsRecipeInSkillLine")[1].args)
  end)

  it("leaves out a known recipe GoldCap does not price", function()
    load({ recipes = { [1] = potion(), [2] = potion({ isSalvageRecipe = true }) }, filtered = { 1, 2 }, professionID = 5 })
    assert.same({ 1 }, CC.KnownRecipes())
  end)

  it("falls back to GetAllRecipeIDs only when GetFilteredRecipeIDs is missing", function()
    load({ recipes = { [1] = potion(), [4] = potion() }, all = { 1, 4 }, professionID = 5,
      absent = { GetFilteredRecipeIDs = true } })
    assert.same({ 1, 4 }, CC.KnownRecipes())
    restore()
    load({ recipes = { [1] = potion(), [4] = potion() }, filtered = { 4 }, all = { 1, 4 }, professionID = 5 })
    assert.same({ 4 }, CC.KnownRecipes())
    assert.equal(0, #TS.callsOf("GetAllRecipeIDs"))
  end)

  it("reads the allocation and the crafted item the window shows", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, level = 2, output = 901, guid = "Item-1-2",
      allocations = { [1] = { { itemID = 101, q = 2 }, { itemID = 102, q = 1 } }, [2] = { { itemID = 300, q = 1 } } } } })
    assert.same({ recipeID = 7, level = 2, output = 901, learned = true,
      alloc = { [1] = { { itemID = 101, q = 2 }, { itemID = 102, q = 1 } }, [2] = { { itemID = 300, q = 1 } } } },
      CC.OpenRecipe())
    local out = TS.callsOf("GetRecipeOutputItemData")
    assert.equal(1, #out)
    assert.equal(7, out[1].args[1])
    assert.equal(TS.reagentInfoTbl, out[1].args[2])
    assert.equal("Item-1-2", out[1].args[3])
  end)

  it("says whether the character has learned the open recipe", function()
    load({ recipes = { [7] = potion({ learned = false }) }, open = { recipeID = 7, allocations = {} } })
    assert.is_false(CC.OpenRecipe().learned)
  end)

  it("leaves a slot out when the player has nothing allocated for it", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = { [2] = { { itemID = 300, q = 1 } } } } })
    assert.same({ [2] = { { itemID = 300, q = 1 } } }, CC.OpenRecipe().alloc)
  end)

  it("reads nothing when the recipes page is not on screen, or a recraft is open", function()
    load({ recipes = { [7] = potion() } })
    assert.is_nil(CC.OpenRecipe())
    restore()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7 } })
    TS.frame:Hide()
    assert.is_nil(CC.OpenRecipe())
    restore()
    load({ recipes = { [7] = potion({ isRecraft = true }) }, open = { recipeID = 7 } })
    assert.is_nil(CC.OpenRecipe())
  end)

  it("reads nothing for an item being recrafted, whose recipe info is the normal recipe's", function()
    -- Recrafting an item opens its normal recipe (isRecraft false) with a recraft transaction.
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, recraft = true,
      allocations = { [1] = { { itemID = 101, q = 3 } } } } })
    assert.is_nil(CC.OpenRecipe())
    restore()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, recraft = false } })
    assert.is_not_nil(CC.OpenRecipe())
  end)

  it("is not the character's own list for a guild, guild member, linked, NPC or runeforging view", function()
    for _, flag in ipairs({ "guild", "guildMember", "linked", "npc", "runeforging" }) do
      load({ external = { [flag] = true } })
      assert.is_false(CC.IsOwnList(), flag)
      restore()
    end
    load({ external = {} })
    assert.is_true(CC.IsOwnList())
    restore()
    load({ external = {}, absent = { IsRuneforging = true } })
    assert.is_true(CC.IsOwnList())
  end)

  it("prices a reagent at the vendor price GoldCap knows, else its trusted market price", function()
    load({})
    VENDOR[101] = 250
    VALUES[101] = commodity(900)
    VALUES[102] = commodity(450)
    -- An imported realm item with only its own realm's median is not a price to cost with.
    VALUES[103] = { mv = 5000, ts = 0, source = "import", kind = "realm_item" }
    assert.equal(250, CC.UnitOf(101))
    assert.equal(450, CC.UnitOf(102))
    assert.is_nil(CC.UnitOf(103))
    assert.is_nil(CC.UnitOf(104))
  end)

  it("reads sold per day with the sell price", function()
    load({})
    VALUES[900] = commodity(10000, 12)
    assert.same({ 10000, 12 }, { CC.SellOf(900) })
    assert.same({}, { CC.SellOf(901) })
  end)

  it("prices a recipe with the window's allocation through the profit maths", function()
    load({ recipes = { [7] = potion() } })
    VALUES[101], VALUES[103], VALUES[300], VALUES[900] = commodity(500), commodity(400), commodity(100), commodity(10000)
    local r = CC.Snapshot(7)
    assert.same({ cost = 1300, sells = 19000, profit = 17700 }, CC.ProfitOf(r))
    assert.same({ cost = 1600, sells = 19000, profit = 17400 },
      CC.ProfitOf(r, { recipeID = 7, alloc = { [1] = { { itemID = 101, q = 3 } } } }))
    -- Another recipe's allocation is not this one's.
    assert.same({ cost = 1300, sells = 19000, profit = 17700 },
      CC.ProfitOf(r, { recipeID = 8, alloc = { [1] = { { itemID = 101, q = 3 } } } }))
  end)

  it("counts bags, bank, reagent bank and warband bank", function()
    load({ counts = { [101] = 3 } })
    assert.equal(3, CC.CountOf(101))
    assert.equal(0, CC.CountOf(102))
    assert.same({ 101, true, false, true, true }, TS.callsOf("GetItemCount")[1].args)
  end)

  it("asks how many crafts the bags allow, and says 0 when it cannot tell", function()
    local r = potion()
    r.craftable = 4
    load({ recipes = { [7] = r } })
    assert.equal(4, CC.Craftable(7, 2))
    assert.same({ 7, 2 }, TS.callsOf("GetCraftableCount")[1].args)
    assert.equal(0, CC.Craftable(8))
  end)

  it("names a missing reagent, a currency, or an item the client has not loaded", function()
    load({ names = { [101] = "Item A" }, currencies = { [3008] = "Valorstones" } })
    assert.equal("Item A", CC.MissingName({ itemID = 101 }))
    assert.equal("Item 102", CC.MissingName({ itemID = 102 }))
    assert.equal("Valorstones", CC.MissingName({ currencyID = 3008 }))
  end)

  it("folds the owned auctions into this character's store", function()
    load({ owned = { { auctionID = 1, itemKey = { itemID = 900 }, quantity = 4, status = 0 },
      { auctionID = 2, itemKey = { itemID = 900 }, quantity = 2, status = 1 } } })
    assert.is_true(CC.ReadListed())
    local listed, at = GC.CraftQueue.Listed("Name-Realm")
    assert.same({ [900] = 4 }, listed)
    assert.is_number(at)
    assert.equal("Name-Realm", CC.Char())
  end)

  it("reads no auctions when there is no character to file them under", function()
    load({ owned = {} })
    GC.Ledger = { Context = function() return { char = nil } end }
    assert.is_false(CC.ReadListed())
    assert.equal(0, #TS.callsOf("GetOwnedAuctions"))
  end)
end)
