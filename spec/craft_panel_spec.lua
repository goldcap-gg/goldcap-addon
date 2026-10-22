local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local TS = require("spec.support.trade_skill")

-- UI/CraftPanel.lua: GoldCap's panel beside the profession window. Worth crafting lists the
-- character's known recipes of the open profession by profit per craft, with profit an hour where
-- the market's daily sales are known, and marks slow sellers; a recipe GoldCap cannot price is
-- counted, never ranked as 0.
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

  for _, flag in ipairs({ "guild", "linked", "npc" }) do
    it("hides for a guild, linked or NPC profession list (" .. flag .. ")", function()
      load({ external = { [flag] = true } })
      prices()
      assert.is_false(show():IsShown())
    end)
  end

  it("lists known recipes by profit per craft, with profit an hour where daily sales are known", function()
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
    assert.equal(GC.L["%s an hour"]:format(GC.Util.Money(GC.CraftMath.PerHour(900, 12, 1))), first.hour:GetText())
    assert.is_true(first.hour:IsShown())
    assert.is_false(first.slow:IsShown())
    assert.is_false(second.hour:IsShown())
    assert.is_false(second.slow:IsShown())
    assert.is_true(third.slow:IsShown())
    assert.equal(GC.L["Slow seller"], third.slow:GetText())
    -- Rows stack in that order, each under the one before.
    local _, above = third.frame:GetPoint(1)
    assert.equal(second.frame, above)
  end)

  it("paints profit green and a loss red", function()
    load()
    prices()
    VALUES[102] = commodity(5000)
    show()
    local last = P._rows[#P._rows].widget
    assert.equal(GC.Util.Money(1900 - 5000), last.profit:GetText())
    local r, g, b = last.profit:GetTextColor()
    assert.same(GC.Theme.color.red, { r, g, b })
    r, g, b = P._rows[1].widget.profit:GetTextColor()
    assert.same(GC.Theme.color.green, { r, g, b })
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

  it("reads nothing while the recipes page is not on screen", function()
    load()
    prices()
    show()
    TS.page:Hide()
    local asked = #TS.callsOf("GetFilteredRecipeIDs")
    P.Refresh()
    assert.equal(asked, #TS.callsOf("GetFilteredRecipeIDs"))
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
