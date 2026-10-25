local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local TS = require("spec.support.trade_skill")

-- UI/CraftPanel.lua: GoldCap's panel beside the profession window. Worth crafting lists the
-- character's known recipes of the open profession that make a profit by profit
-- per craft, with how many sell a day where that is known, and marks slow sellers; a recipe that
-- makes no profit, and one GoldCap cannot price, are counted, never listed.
describe("craft panel", function()
  local GC, P, restore, VALUES

  local function commodity(mv, sold)
    return { mv = mv, sold = sold, ts = 0, source = "import", kind = "region_commodity" }
  end

  -- Recipe id makes item 900 + id from one of item 100 + id.
  local function recipe(id, name, extra)
    return { info = TS.info(id, name, extra), schematic = TS.schematic(id, 900 + id, { TS.slot(1, 1, TS.items(100 + id)) }) }
  end

  -- A, B and C at 900, 500 and 200 a craft (each sells for 1,900 after the cut), selling 12, an
  -- unknown number and half a time a day; D has no price for its reagent.
  local function world(opts)
    opts = opts or {}
    opts.recipes = opts.recipes or { [1] = recipe(1, "A"), [2] = recipe(2, "B"), [3] = recipe(3, "C"), [4] = recipe(4, "D") }
    opts.filtered = opts.filtered or { 3, 4, 1, 2 }
    opts.professionID = 2823
    return opts
  end

  local function prices()
    VALUES[101], VALUES[102], VALUES[103] = commodity(1000), commodity(1400), commodity(1700)
    VALUES[901], VALUES[902], VALUES[903], VALUES[904] = commodity(2000, 12), commodity(2000), commodity(2000, 0.5), commodity(2000)
  end

  local function load(opts)
    restore = TS.install(world(opts))
    GC = TS.craftGC()
    VALUES = {}
    GC.Data = { GetItemValue = function(id) return VALUES[id] end }
    GC.AppRuns = { VendorUnitFor = function() return nil end }
    GC.Ledger = { Context = function() return { char = "Name-Realm" } end }
    GC.db = {}
    helper.loadModule("UI/CraftPanel.lua", GC)
    P = GC.CraftPanel
  end

  local function show()
    local ev = P._events
    ev:GetScript("OnEvent")(ev, "TRADE_SKILL_SHOW")
    TS.runTimers()
    return P._frame
  end

  after_each(function()
    if restore then restore() end
    W.unknownEvents = {}
  end)

  it("opens beside the profession window on its recipes page", function()
    load()
    local f = show()
    assert.equal(TS.page, f:GetParent())
    assert.same({ "TOPLEFT", TS.frame, "TOPRIGHT", 0, 0 }, { f:GetPoint(1) })
    assert.equal(300, f:GetWidth())
    assert.equal(TS.frame:GetHeight(), f:GetHeight())
    assert.is_true(f:IsShown())
  end)

  it("is kept on screen when the window leaves no room to its right", function()
    -- The recipes page is 942 wide: on a 16:10 or 4:3 screen the panel's right edge, where the
    -- profit column sits, would fall off. Clamped, the client slides it back over the window.
    load()
    assert.is_true(W.state(show()).clamped)
  end)

  for _, flag in ipairs({ "guild", "linked", "npc" }) do
    it("hides for a guild, linked or NPC profession list (" .. flag .. ")", function()
      load({ external = { [flag] = true } })
      prices()
      assert.is_false(show():IsShown())
    end)
  end

  it("lists known recipes that make a profit by profit per craft, with sales a day where known", function()
    load()
    prices()
    local f = show()
    local ids = {}
    for _, row in ipairs(P._rows) do ids[#ids + 1] = row.recipeID end
    assert.same({ 1, 2, 3 }, ids)
    assert.equal(GC.L["Worth crafting"], f.worth.heading:GetText())
    local first, second, third = P._rows[1].widget, P._rows[2].widget, P._rows[3].widget
    assert.equal("A", first.name:GetText())
    assert.equal(GC.Util.Money(900), first.profit:GetText())
    assert.equal(GC.L["Sells about %s a day"]:format("12"), first.pace:GetText())
    assert.is_true(first.pace:IsShown())
    assert.is_false(first.slow:IsShown())
    assert.is_false(second.pace:IsShown())
    assert.is_false(second.slow:IsShown())
    assert.is_true(third.slow:IsShown())
    assert.is_false(third.pace:IsShown())
    assert.equal(GC.L["Slow seller"], third.slow:GetText())
    -- Rows stack in that order, each under the one before.
    local _, above = third.frame:GetPoint(1)
    assert.equal(second.frame, above)
  end)

  it("paints profit green", function()
    load()
    prices()
    show()
    local r, g, b = P._rows[1].widget.profit:GetTextColor()
    assert.same(GC.Theme.color.green, { r, g, b })
  end)

  it("lists only recipes that make a profit and counts the rest under the list", function()
    load()
    prices()
    local f = show()
    assert.is_false(f.worth.unprofitable:IsShown())
    VALUES[102] = commodity(5000) -- B loses 3,100 a craft
    P.Refresh()
    local ids = {}
    for _, row in ipairs(P._rows) do ids[#ids + 1] = row.recipeID end
    assert.same({ 1, 3 }, ids)
    assert.equal(GC.L["1 recipe makes no profit now"], f.worth.unprofitable:GetText())
    assert.is_true(f.worth.unprofitable:IsShown())
    -- Stacked above the unpriced line (D), which sits above the note.
    local _, relative = f.worth.unprofitable:GetPoint(1)
    assert.equal(f.worth.unpriced, relative)
    VALUES[103] = commodity(1900) -- C makes exactly 0
    P.Refresh()
    assert.equal(GC.L["%d recipes make no profit now"]:format(2), f.worth.unprofitable:GetText())
    VALUES[104] = commodity(1900) -- D priced, makes 0
    P.Refresh()
    assert.is_false(f.worth.unpriced:IsShown())
    assert.equal(GC.L["%d recipes make no profit now"]:format(3), f.worth.unprofitable:GetText())
    _, relative = f.worth.unprofitable:GetPoint(1)
    assert.equal(f.worth.note, relative)
  end)

  it("says no recipe makes a profit when every priced recipe loses, and no price when none is priced", function()
    load()
    prices()
    VALUES[101], VALUES[102], VALUES[103] = commodity(5000), commodity(5000), commodity(5000)
    local f = show()
    assert.same({}, P._rows)
    assert.is_true(f.worth.empty:IsShown())
    assert.equal(GC.L["No recipe here makes a profit now"], f.worth.empty:GetText())
    assert.is_false(f.worth.unprofitable:IsShown()) -- the empty line says it already
    VALUES = {}
    P.Refresh()
    assert.equal(GC.L["No recipe here has a GoldCap price yet"], f.worth.empty:GetText())
    assert.is_false(f.worth.unprofitable:IsShown())
  end)

  it("says how many sell a day: rounded, grouped, and Slow seller alone under one a day", function()
    load()
    prices()
    VALUES[901], VALUES[902], VALUES[903] = commodity(2000, 2.6), commodity(2000, 1234), commodity(2000, 1)
    show()
    local text = {}
    for _, row in ipairs(P._rows) do
      local w = row.widget
      text[row.recipeID] = w.pace:IsShown() and w.pace:GetText() or false
      assert.is_false(w.slow:IsShown())
    end
    assert.equal(GC.L["Sells about %s a day"]:format("3"), text[1])
    assert.equal(GC.L["Sells about %s a day"]:format(GC.Util.Grouped(1234)), text[2])
    assert.equal(GC.L["Sells about %s a day"]:format("1"), text[3])
    VALUES[901], VALUES[902], VALUES[903] = commodity(2000, 0.9), commodity(2000, 0), commodity(2000)
    P.Refresh()
    for _, row in ipairs(P._rows) do
      local w = row.widget
      assert.is_false(w.pace:IsShown())
      assert.equal(row.recipeID ~= 3, w.slow:IsShown())
    end
  end)

  it("counts recipes with no price in the footer, never as rows", function()
    load()
    prices()
    local f = show()
    for _, row in ipairs(P._rows) do assert.is_not.equal(4, row.recipeID) end
    assert.equal(GC.L["1 recipe has no GoldCap price for a reagent or what it makes"], f.worth.unpriced:GetText())
    assert.is_true(f.worth.unpriced:IsShown())
    assert.equal(GC.L["Each reagent at its cheapest quality"], f.worth.note:GetText())
    VALUES[101] = nil
    P.Refresh()
    assert.equal(GC.L["%d recipes have no GoldCap price for a reagent or what it makes"]:format(2), f.worth.unpriced:GetText())
    VALUES[101], VALUES[104] = commodity(1000), commodity(100)
    P.Refresh()
    assert.is_false(f.worth.unpriced:IsShown())
  end)

  it("shows the empty sentence when nothing can be priced", function()
    load()
    local f = show()
    assert.same({}, P._rows)
    assert.is_true(f.worth.empty:IsShown())
    assert.equal(GC.L["No recipe here has a GoldCap price yet"], f.worth.empty:GetText())
    prices()
    P.Refresh()
    assert.is_false(f.worth.empty:IsShown())
  end)

  it("gives each row the height its wrapped name needs", function()
    load({ recipes = { [1] = recipe(1, string.rep("Long name ", 12)), [2] = recipe(2, "B") }, filtered = { 1, 2 } })
    prices()
    show()
    local long, short = P._rows[1].widget, P._rows[2].widget
    assert.is_true(W.state(long.name).wordWrap)
    assert.is_nil(W.state(long.name).maxLines)
    assert.is_true(long.frame:GetHeight() > short.frame:GetHeight())
  end)

  it("repaints on a list update and a learned recipe, once per frame", function()
    load({ filtered = { 1 } })
    prices()
    show()
    assert.equal(1, #P._rows)
    local ev = P._events
    for _, event in ipairs({ "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED", "BAG_UPDATE_DELAYED" }) do
      assert.is_true(ev:IsEventRegistered(event), event)
    end
    TS.opts.filtered = { 1, 2 }
    ev:GetScript("OnEvent")(ev, "NEW_RECIPE_LEARNED", 2)
    ev:GetScript("OnEvent")(ev, "TRADE_SKILL_LIST_UPDATE")
    TS.trigger("ProfessionsRecipeListMixin.Event.OnRecipeSelected", TS.info(2, "B"))
    assert.equal(1, #TS.timers)
    TS.runTimers()
    assert.equal(2, #P._rows)
  end)

  it("never reprices Worth crafting for a bag change: nothing in it depends on the bags", function()
    load()
    prices()
    show()
    local asked = #TS.callsOf("GetFilteredRecipeIDs")
    local ev = P._events
    ev:GetScript("OnEvent")(ev, "BAG_UPDATE_DELAYED")
    TS.runTimers()
    assert.equal(asked, #TS.callsOf("GetFilteredRecipeIDs"))
  end)

  it("reads nothing while the recipes page is not on screen", function()
    load()
    prices()
    show()
    TS.page:Hide()
    local asked = #TS.callsOf("GetFilteredRecipeIDs")
    P.Refresh()
    assert.equal(asked, #TS.callsOf("GetFilteredRecipeIDs"))
  end)

  describe("putting recipes in the queue", function()
    local savedUIParent, savedMenu

    before_each(function()
      savedUIParent, savedMenu = _G.UIParent, _G.MenuUtil
    end)

    after_each(function()
      _G.UIParent, _G.MenuUtil = savedUIParent, savedMenu
    end)

    -- The recipe form shows recipe 2 (B); the editor is the real one, BUY's popup.
    local function loadOpen(opts)
      opts = opts or {}
      opts.open = opts.open or { recipeID = 2, allocations = {} }
      load(opts)
      _G.UIParent = W.CreateFrame("Frame")
      helper.loadModule("UI/BuyCapEditor.lua", GC)
      prices()
      return show()
    end

    local function editor() return GC.BuyCapEditor._frame end

    local function commit(text)
      editor().box:SetText(text)
      editor().set:GetScript("OnClick")(editor().set)
    end

    it("shows the open recipe with Add to queue and Restock to", function()
      local f = loadOpen()
      local card = f.card
      assert.is_true(card:IsShown())
      assert.equal(GC.L["This recipe"], card.heading:GetText())
      assert.equal("B", card.name:GetText())
      assert.equal(GC.L["Add to queue"], card.add.label)
      assert.equal(GC.L["Restock to"], card.restock.label)
      -- The view switch sits under the card, and the list under the switch.
      local _, above = f.switch:GetPoint(1)
      assert.equal(card, above)
      _, above = f.body:GetPoint(1)
      assert.equal(f.switch, above)
    end)

    it("Add to queue asks how many and adds that many crafts", function()
      local f = loadOpen()
      f.card.add:GetScript("OnClick")(f.card.add)
      assert.is_true(editor():IsShown())
      assert.equal("1", editor().box:GetText())
      assert.equal(GC.L["How many crafts of %s?"]:format("B"), editor().title:GetText())
      assert.equal(GC.L["Add"], editor().set.label)
      commit("0")
      assert.is_true(editor():IsShown())
      assert.equal(GC.L["Type a whole number"], editor().preview:GetText())
      assert.same({}, GC.CraftQueue.Entries("Name-Realm"))
      commit("3")
      assert.is_false(editor():IsShown())
      local entries = GC.CraftQueue.Entries("Name-Realm")
      assert.equal(1, #entries)
      assert.equal(2, entries[1].recipe.recipeID)
      assert.equal(3, entries[1].count)
    end)

    it("Restock to asks for a target, and 0 takes the recipe off", function()
      local f = loadOpen()
      local changed = 0
      P.OnQueueChanged = function() changed = changed + 1 end
      f.card.restock:GetScript("OnClick")(f.card.restock)
      assert.equal(GC.L["Restock %s to how many? 0 takes it off the queue."]:format("B"), editor().title:GetText())
      assert.equal(GC.L["Save"], editor().set.label)
      commit("12")
      assert.equal(12, GC.CraftQueue.Entries("Name-Realm")[1].restock)
      assert.equal(1, changed)
      assert.equal(1, #TS.timers)
      TS.runTimers()
      f.card.restock:GetScript("OnClick")(f.card.restock)
      assert.equal("12", editor().box:GetText())
      commit("0")
      assert.same({}, GC.CraftQueue.Entries("Name-Realm"))
      assert.equal(2, changed)
    end)

    it("a Worth crafting row's right click offers both", function()
      loadOpen()
      local entries, owner = {}, nil
      _G.MenuUtil = { CreateContextMenu = function(o, generator)
        owner = o
        generator(nil, {
          CreateTitle = function(_, text) entries[#entries + 1] = { title = text } end,
          CreateButton = function(_, text, fn) entries[#entries + 1] = { text = text, fn = fn } end,
        })
      end }
      local row = P._rows[2].widget
      assert.equal("B", row.name:GetText())
      row.frame:GetScript("OnClick")(row.frame, "RightButton")
      assert.equal(row.frame, owner)
      local texts = {}
      for _, e in ipairs(entries) do if e.text then texts[#texts + 1] = e.text end end
      assert.same({ GC.Util.ClientText(GC.L["Add to queue"]), GC.Util.ClientText(GC.L["Restock to"]) }, texts)
      entries[#entries - 1].fn()
      commit("2")
      assert.equal(2, GC.CraftQueue.Entries("Name-Realm")[1].count)
      assert.equal(2, GC.CraftQueue.Entries("Name-Realm")[1].recipe.recipeID)
    end)

    it("hides This recipe for a recipe GoldCap does not price, and when the store is newer", function()
      local f = loadOpen({ open = { recipeID = 9, allocations = {} },
        recipes = { [1] = recipe(1, "A"), [2] = recipe(2, "B"), [9] = recipe(9, "Salvage", { isSalvageRecipe = true }) },
        filtered = { 1, 2 } })
      assert.is_false(f.card:IsShown())
      local _, above = f.switch:GetPoint(1)
      assert.equal(f.title, above)
      restore()
      f = loadOpen()
      GC.db.craft = { v = 2, chars = {} }
      P.Refresh()
      assert.is_false(f.card:IsShown())
    end)

    it("hides This recipe for a recipe the character has not learned: it can never be queued", function()
      -- Blizzard's list shows unlearned recipes too, and selecting one fills the form.
      local f = loadOpen({ open = { recipeID = 9, allocations = {} },
        recipes = { [1] = recipe(1, "A"), [2] = recipe(2, "B"), [9] = recipe(9, "Unlearned", { learned = false }) },
        filtered = { 1, 2, 9 } })
      assert.is_false(f.card:IsShown())
      assert.is_nil(f.card.recipe)
      local _, above = f.switch:GetPoint(1)
      assert.equal(f.title, above)
      -- Nothing reaches the queue from it.
      assert.same({}, GC.CraftQueue.Entries("Name-Realm"))
    end)

    it("sizes each button to its label in every locale, stacking them when they do not fit", function()
      local f = loadOpen()
      for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
      local inner = f.card:GetWidth() - 2 * 8
      local besideSomewhere = false
      for _, code in ipairs(helper.localeCodes()) do
        GC.ActivateLocale(code)
        P.Refresh()
        local add, restock = f.card.add, f.card.restock
        for _, b in ipairs({ add, restock }) do
          assert.is_true(b:GetWidth() >= b.text:GetUnboundedStringWidth(), code .. ": " .. tostring(b.label))
          assert.is_true(b:GetWidth() <= inner, code .. ": " .. tostring(b.label))
        end
        local point, relative, relativePoint = restock:GetPoint(1)
        assert.equal(add, relative, code)
        if add:GetWidth() + 8 + restock:GetWidth() > inner then
          assert.same({ "TOPLEFT", "BOTTOMLEFT" }, { point, relativePoint }, code)
        else
          assert.same({ "LEFT", "RIGHT" }, { point, relativePoint }, code)
          besideSomewhere = true
        end
        assert.is_true(W.state(f.card.name).wordWrap)
      end
      GC.ActivateLocale(nil)
      assert.is_true(besideSomewhere)
      -- Two labels too long to sit side by side: one under the other, the card taller for it.
      local beside = f.card:GetHeight()
      GC.L = setmetatable({}, { __index = function(_, key) return key .. " " .. string.rep("w", 14) end })
      P.Refresh()
      local point, relative, relativePoint = f.card.restock:GetPoint(1)
      assert.same({ "TOPLEFT", f.card.add, "BOTTOMLEFT" }, { point, relative, relativePoint })
      assert.is_true(f.card:GetHeight() > beside)
    end)
  end)

  it("registers each event through pcall", function()
    W.unknownEvents = { NEW_RECIPE_LEARNED = true }
    load()
    local ev = P._events
    assert.is_false(ev:IsEventRegistered("NEW_RECIPE_LEARNED"))
    for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "BAG_UPDATE_DELAYED" }) do
      assert.is_true(ev:IsEventRegistered(event), event)
    end
    local file = assert(io.open("GoldCap/UI/CraftPanel.lua", "r"))
    local src = file:read("*a"):gsub("%-%-[^\n]*", "")
    file:close()
    assert.is_nil(src:find(":RegisterEvent%("))
    assert.is_truthy(src:find("pcall%(events%.RegisterEvent, events,"))
    assert.is_nil(src:find("hooksecurefunc", 1, true))
  end)
end)
