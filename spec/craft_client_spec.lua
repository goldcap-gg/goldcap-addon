local helper = require("spec.spec_helper")
local TS = require("spec.support.trade_skill")
local W = require("spec.support.wow_frames")

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

  it("refuses a recipe whose required reagent needs a count of its own, and ignores one on an optional slot", function()
    -- A variable quantity: one reagent of the slot takes 5 where the slot says 3. No 12.x recipe
    -- has one on a required slot; if one ever does, a figure at the slot's count would be wrong.
    local r = potion()
    r.schematic.reagentSlotSchematics[1].variableQuantities = { { reagent = { itemID = 103 }, quantity = 5 } }
    load({ recipes = { [7] = r } })
    assert.is_nil(CC.Snapshot(7))
    restore()
    r = potion()
    r.schematic.reagentSlotSchematics[3].variableQuantities = { { reagent = { itemID = 400 }, quantity = 2 } }
    load({ recipes = { [7] = r } })
    assert.is_not_nil(CC.Snapshot(7))
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

  -- Probe A3 (retail 12.1.5, 2026-10-26): CraftRecipe with the window shut crafts nothing and says
  -- nothing. A recipe is craftable here only on the player's own window, on its skill line.
  it("says a recipe is craftable here only on the player's own window, on its skill line", function()
    local other = potion()
    other.inSkillLine = false
    other.professionName = "Midnight Tailoring"
    load({ recipes = { [1] = potion(), [3] = other }, filtered = { 1, 3 }, professionID = 2823 })
    assert.is_true(CC.CraftableHere(1))
    assert.same({ false, "Midnight Tailoring" }, { CC.CraftableHere(3) })

    TS.frame:Hide()
    assert.is_false((CC.CraftableHere(1)))
    TS.frame:Show()
    TS.opts.external = { linked = true }
    assert.is_false((CC.CraftableHere(1)))
  end)

  it("lists a ranked recipe once, at the highest rank the character learned", function()
    -- Ranks 1 to 3 of one recipe (11, 12, 13), chained by previousRecipeID and nextRecipeID;
    -- the character knows ranks 1 and 2. Blizzard's list shows the chain once.
    local function rank(id, prev, nxt, learned)
      local r = potion()
      r.info = TS.info(id, "Ranked", { previousRecipeID = prev, nextRecipeID = nxt, learned = learned })
      return r
    end
    load({ recipes = { [11] = rank(11, nil, 12, true), [12] = rank(12, 11, 13, true), [13] = rank(13, 12, nil, false),
      [1] = potion() }, filtered = { 11, 12, 13, 1 }, professionID = 5 })
    assert.same({ 12, 1 }, CC.KnownRecipes())
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
      link = "|Hitem:901::|h[Potion]|h",
      allocations = { [1] = { { itemID = 101, q = 2 }, { itemID = 102, q = 1 } }, [2] = { { itemID = 300, q = 1 } } } } })
    assert.same({ recipeID = 7, level = 2, output = 901, link = "|Hitem:901::|h[Potion]|h", learned = true,
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
    -- A currency the client cannot name reads as one, never as a bare number.
    assert.equal(GC.L["Currency %d"]:format(3010), CC.MissingName({ currencyID = 3010 }))
    assert.equal("Currency 3010", CC.MissingName({ currencyID = 3010 }))
  end)

  it("reads an item's icon, and none for an item the client has none for", function()
    load({ icons = { [900] = 4639565 } })
    assert.equal(4639565, CC.IconOf(900))
    assert.is_nil(CC.IconOf(901))
    assert.is_nil(CC.IconOf(nil))
  end)

  it("counts what the character holds of a currency, and none of one the client does not know", function()
    load({ currencies = { [3008] = "Valorstones", [3010] = "Crests" }, currencyHeld = { [3008] = 120 } })
    assert.equal(120, CC.CurrencyCount(3008))
    assert.equal(0, CC.CurrencyCount(3010))
    assert.equal(0, CC.CurrencyCount(4040))
    assert.equal(0, CC.CurrencyCount(nil))
  end)

  it("names the profession whose window is open, with its icon", function()
    load({ professionID = 171, professionName = "Midnight Alchemy", professionTexture = 136240 })
    assert.same({ "Midnight Alchemy", 136240 }, { CC.Profession() })
    assert.same({ 171 }, TS.callsOf("GetTradeSkillTexture")[1].args)
  end)

  it("falls back to the base profession, and knows none when the client has none", function()
    load({ professionID = 0, baseProfession = { professionID = 164, professionName = "Blacksmithing" },
      professionTexture = 136241 })
    assert.same({ "Blacksmithing", 136241 }, { CC.Profession() })
    restore()
    load({})
    assert.is_nil(CC.Profession())
    restore()
    load({ professionID = 171, professionName = "Alchemy", absent = { GetTradeSkillTexture = true } })
    assert.same({ "Alchemy", nil }, { CC.Profession() })
  end)

  it("opens a recipe of the open profession in the window, and no other", function()
    load({ professionID = 171, recipes = { [7] = potion(), [8] = potion() } })
    TS.opts.recipes[8].inSkillLine = false
    TS.frame:Show()
    CC.Open(7)
    CC.Open(8)
    assert.equal(1, #TS.callsOf("OpenRecipe"))
    assert.same({ 7 }, TS.callsOf("OpenRecipe")[1].args)
    TS.frame:Hide()
    CC.Open(7)
    assert.equal(1, #TS.callsOf("OpenRecipe"))
  end)

  -- The run of crafts the client is making, as GoldCap counts it. Blizzard's crafting page
  -- (Blizzard_ProfessionsCrafting.lua) begins each cast of a run with TRADE_SKILL_CRAFT_BEGIN and
  -- ends the run with UPDATE_TRADESKILL_CAST_STOPPED; the player's casts carry the unit, the cast's
  -- GUID and its spell (UnitDocumentation.lua), a recipe's spell being the recipe.
  describe("Repeating", function()
    local function fire(event, ...)
      local ev = CC._events
      ev:GetScript("OnEvent")(ev, event, ...)
    end

    local function cast(event, guid, spellID) fire(event, "player", guid, spellID) end

    it("listens for the events Blizzard's crafting page ends a run on, and the player's casts", function()
      load({})
      for _, event in ipairs({ "TRADE_SKILL_CRAFT_BEGIN", "UPDATE_TRADESKILL_CAST_STOPPED", "TRADE_SKILL_CLOSE",
          "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
        assert.is_true(CC._events:IsEventRegistered(event), event)
      end
    end)

    it("is nothing before a craft begins", function()
      load({})
      assert.is_nil(CC.Repeating())
    end)

    it("counts a run by its own finished casts, whatever moment GetRemainingRecasts drops", function()
      load({})
      TS.opts.recasts = 2
      cast("UNIT_SPELLCAST_START", "Cast-1", 7)
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      assert.same({ 7, 3, 3 }, { CC.Repeating() })
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-1", 7)
      assert.same({ 7, 2, 3 }, { CC.Repeating() })
      -- The next cast: the client's count may drop before it, as it begins, or later.
      TS.opts.recasts = 0
      cast("UNIT_SPELLCAST_START", "Cast-2", 7)
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      assert.same({ 7, 2, 3 }, { CC.Repeating() })
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-2", 7)
      TS.opts.recasts = 1
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      assert.same({ 7, 1, 3 }, { CC.Repeating() })
      -- Another spell's cast is none of the run's.
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-9", 99)
      assert.same({ 7, 1, 3 }, { CC.Repeating() })
      -- The last cast made: the run is over before the client says it stopped.
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-3", 7)
      assert.is_nil(CC.Repeating())
      fire("UPDATE_TRADESKILL_CAST_STOPPED", false)
      assert.is_nil(CC.Repeating())
      -- The next run of the same recipe is a run of its own.
      TS.opts.recasts = 1
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      assert.same({ 7, 2, 2 }, { CC.Repeating() })
    end)

    it("sizes a run Blizzard's own Create started by the casts the client says it has", function()
      load({})
      TS.opts.recasts = 3
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      assert.same({ 7, 4, 4 }, { CC.Repeating() })
    end)

    it("sizes a run GoldCap's press started by the press, and holds the press as crafting until it begins", function()
      load({})
      TS.now = 10
      CC.Started(7, 5)
      assert.same({ 7, 5, 5 }, { CC.Repeating() })
      TS.now = 10.9
      assert.same({ 7, 5, 5 }, { CC.Repeating() })
      TS.opts.recasts = 2
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      TS.now = 20
      assert.same({ 7, 5, 5 }, { CC.Repeating() })
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-1", 7)
      assert.same({ 7, 4, 5 }, { CC.Repeating() })
    end)

    it("lets a press go when no craft begins within about a second, or when the craft ends first", function()
      load({})
      TS.now = 10
      CC.Started(7, 5)
      TS.now = 11.1
      assert.is_nil(CC.Repeating())
      for _, ending in ipairs({ { "UPDATE_TRADESKILL_CAST_STOPPED", false }, { "TRADE_SKILL_CLOSE" },
          { "UNIT_SPELLCAST_FAILED", "player", "Cast-1", 7 }, { "UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-1", 7 } }) do
        CC.Started(7, 5)
        fire(ending[1], ending[2], ending[3], ending[4])
        assert.is_nil(CC.Repeating(), ending[1])
      end
      -- Another spell failing is not the press.
      CC.Started(7, 5)
      cast("UNIT_SPELLCAST_FAILED", "Cast-2", 99)
      assert.same({ 7, 5, 5 }, { CC.Repeating() })
      -- Blizzard's own Create of another recipe began first: that is the run.
      TS.opts.recasts = 0
      fire("TRADE_SKILL_CRAFT_BEGIN", 8)
      assert.same({ 8, 1, 1 }, { CC.Repeating() })
    end)

    it("ends a run on a failed or interrupted cast only when it is the running cast", function()
      load({})
      TS.opts.recasts = 2
      cast("UNIT_SPELLCAST_START", "Cast-1", 7)
      TS.casting = { guid = "Cast-1", spellID = 7 }
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      -- A press refused while the craft is cast (another action is in progress) fails with a GUID
      -- of its own, as Blizzard's cast bar knows (CastingBarFrame.lua, HandleInterruptOrSpellFailed).
      cast("UNIT_SPELLCAST_FAILED", "Cast-2", 7)
      cast("UNIT_SPELLCAST_INTERRUPTED", "Cast-3", 99)
      assert.same({ 7, 3, 3 }, { CC.Repeating() })
      cast("UNIT_SPELLCAST_FAILED", "Cast-1", 7)
      assert.is_nil(CC.Repeating())
      cast("UNIT_SPELLCAST_START", "Cast-4", 7)
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      cast("UNIT_SPELLCAST_INTERRUPTED", "Cast-4", 7)
      assert.is_nil(CC.Repeating())
    end)

    it("ends a run on a failed or interrupted cast of the player when it cannot tell the run's cast", function()
      load({})
      -- The run's cast never seen begin.
      for _, event in ipairs({ "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
        fire("TRADE_SKILL_CRAFT_BEGIN", 7)
        cast(event, "Cast-1", 7)
        assert.is_nil(CC.Repeating(), event)
      end
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      fire("TRADE_SKILL_CLOSE")
      assert.is_nil(CC.Repeating())
      -- A secret GUID, which addon code may not compare, nor count a finished cast by.
      local SECRET, saved = {}, _G.issecretvalue
      _G.issecretvalue = function(v) return v == SECRET end
      finally(function() _G.issecretvalue = saved end)
      TS.opts.recasts = 1
      cast("UNIT_SPELLCAST_START", "Cast-2", 7)
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-2", SECRET)
      assert.same({ 7, 2, 2 }, { CC.Repeating() })
      cast("UNIT_SPELLCAST_FAILED", SECRET, SECRET)
      assert.is_nil(CC.Repeating())
    end)

    -- The client stops a run early when a recast fails (the reagents the window picks ran out): that
    -- recast never began, so its failure carries a GUID of its own, and the player casts nothing.
    it("ends a run whose next cast fails while the player casts nothing", function()
      load({})
      TS.opts.recasts = 4
      cast("UNIT_SPELLCAST_START", "Cast-1", 7)
      TS.casting = { guid = "Cast-1", spellID = 7 }
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-1", 7)
      TS.casting = nil
      -- Another spell refused between two casts is not the run's.
      cast("UNIT_SPELLCAST_FAILED", "Cast-8", 99)
      assert.same({ 7, 4, 5 }, { CC.Repeating() })
      cast("UNIT_SPELLCAST_FAILED", "Cast-2", 7)
      assert.is_nil(CC.Repeating())
    end)

    -- TRADE_SKILL_CRAFT_BEGIN is a synchronous event: it may fire inside CraftRecipe, before the
    -- press says how many it asked for.
    it("takes the press's count for a run that began before the press said it", function()
      load({})
      TS.opts.recasts = 0
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      CC.Started(7, 5)
      assert.same({ 7, 5, 5 }, { CC.Repeating() })
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-1", 7)
      assert.same({ 7, 4, 5 }, { CC.Repeating() })
      -- A press of another recipe is a press of its own.
      CC.Started(8, 2)
      assert.same({ 7, 4, 5 }, { CC.Repeating() })
    end)

    it("forgets an ended run's cast, so a later run whose cast it never saw begin still ends on its failure", function()
      load({})
      -- A run that stopped.
      cast("UNIT_SPELLCAST_START", "Cast-1", 7)
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      fire("UPDATE_TRADESKILL_CAST_STOPPED", false)
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      cast("UNIT_SPELLCAST_FAILED", "Cast-2", 7)
      assert.is_nil(CC.Repeating())
      -- A run that made all it was asked for.
      cast("UNIT_SPELLCAST_START", "Cast-3", 7)
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      cast("UNIT_SPELLCAST_SUCCEEDED", "Cast-3", 7)
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      cast("UNIT_SPELLCAST_INTERRUPTED", "Cast-4", 7)
      assert.is_nil(CC.Repeating())
    end)

    it("is not ended by another unit's cast or by a scrapping stop", function()
      load({})
      fire("TRADE_SKILL_CRAFT_BEGIN", 7)
      fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 7)
      fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-1", 7)
      fire("UPDATE_TRADESKILL_CAST_STOPPED", true)
      assert.same({ 7, 1, 1 }, { CC.Repeating() })
    end)

    it("registers the player's casts only", function()
      load({})
      for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
          "UNIT_SPELLCAST_INTERRUPTED" }) do
        assert.same({ "player" }, W.state(CC._events).unitEvents[event], event)
      end
    end)
  end)

  it("names a recipe as the client does, by its id when the client has no name for it", function()
    load({ recipes = { [7] = potion() } })
    assert.equal("Potion", CC.RecipeName(7))
    assert.equal("12", CC.RecipeName(12))
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
