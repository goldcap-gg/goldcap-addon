local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local TS = require("spec.support.trade_skill")

-- UI/CraftStrip.lua: GoldCap's strip under the open recipe's reagents. What the reagents the
-- player picked cost, what one craft sells for after the auction house cut, the profit; a reagent
-- or crafted item with no GoldCap price is named instead of a number.
describe("craft strip", function()
  local GC, S, restore, VALUES

  local function commodity(mv, sold)
    return { mv = mv, sold = sold, ts = 0, source = "import", kind = "region_commodity" }
  end

  local function potion(info, slots)
    return {
      info = TS.info(7, "Potion", info),
      schematic = TS.schematic(7, 900, slots or { TS.slot(1, 3, TS.items(101, 102, 103)) }),
    }
  end

  local function load(opts)
    restore = TS.install(opts)
    GC = TS.craftGC()
    VALUES = {}
    GC.Data = { GetItemValue = function(id) return VALUES[id] end }
    GC.AppRuns = { VendorUnitFor = function() return nil end }
    helper.loadModule("UI/CraftStrip.lua", GC)
    S = GC.CraftStrip
  end

  local function show()
    local ev = S._events
    ev:GetScript("OnEvent")(ev, "TRADE_SKILL_SHOW")
    TS.runTimers()
    return S._frame
  end

  local function rgb(fs)
    local r, g, b = fs:GetTextColor()
    return { r, g, b }
  end

  local function shownTexts(f)
    local out = {}
    for _, line in ipairs(f.lines) do
      if line:IsShown() then out[#out + 1] = line:GetText() end
    end
    return out
  end

  after_each(function()
    if restore then restore() end
    _G.AuctionatorCraftingInfoProfessionsFrame = nil
  end)

  it("shows what the reagents cost, what one craft sells for after the cut, and the profit", function()
    load({ recipes = { [7] = potion() },
      open = { recipeID = 7, allocations = { [1] = { { itemID = 103, q = 3 } } } } })
    VALUES[101], VALUES[103], VALUES[900] = commodity(500), commodity(400), commodity(10000)
    local f = show()
    assert.is_true(f:IsShown())
    assert.equal("GoldCap", f.title:GetText())
    local cost, sells = 3 * 400, math.floor(10000 * 0.95)
    assert.same({
      GC.L["Reagents cost %s"]:format(GC.Util.Money(cost)),
      GC.L["One craft sells for %s after the auction house cut"]:format(GC.Util.Money(sells)),
      GC.L["Profit %s"]:format(GC.Util.Money(sells - cost)),
    }, shownTexts(f))
    assert.same({ GC.Theme.color.green[1], GC.Theme.color.green[2], GC.Theme.color.green[3] }, rgb(f.lines[3]))
  end)

  it("prices the reagents the player allocated, and paints a loss red", function()
    load({ recipes = { [7] = potion() },
      open = { recipeID = 7, allocations = { [1] = { { itemID = 101, q = 3 } } } } })
    VALUES[101], VALUES[103], VALUES[900] = commodity(5000), commodity(400), commodity(10000)
    local f = show()
    assert.equal(GC.L["Reagents cost %s"]:format(GC.Util.Money(15000)), f.lines[1]:GetText())
    assert.equal(GC.L["Profit %s"]:format(GC.Util.Money(9500 - 15000)), f.lines[3]:GetText())
    assert.same({ GC.Theme.color.red[1], GC.Theme.color.red[2], GC.Theme.color.red[3] }, rgb(f.lines[3]))
  end)

  it("prices slots the player has no reagents for", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
    VALUES[102], VALUES[103], VALUES[900] = commodity(450), commodity(400), commodity(10000)
    local f = show()
    assert.equal(GC.L["Reagents cost %s"]:format(GC.Util.Money(1200)), f.lines[1]:GetText())
    assert.equal(3, #shownTexts(f))
  end)

  it("names each reagent with no price instead of a figure", function()
    load({ recipes = { [7] = potion(nil, { TS.slot(1, 3, TS.items(101)), TS.slot(2, 2, { { currencyID = 3008 } }) }) },
      open = { recipeID = 7, allocations = {} }, names = { [101] = "Item A" }, currencies = { [3008] = "Valorstones" } })
    VALUES[900] = commodity(10000)
    local f = show()
    assert.same({ "No GoldCap price for Item A, Valorstones" }, shownTexts(f))
  end)

  it("names the crafted item when it has no price", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} }, names = { [900] = "Potion" } })
    VALUES[103] = commodity(400)
    assert.same({ "No GoldCap price for Potion" }, shownTexts(show()))
  end)

  it("hides for a recipe GoldCap does not price", function()
    load({ recipes = { [7] = potion({ isSalvageRecipe = true }) }, open = { recipeID = 7, allocations = {} } })
    VALUES[103], VALUES[900] = commodity(400), commodity(10000)
    assert.is_false(show():IsShown())
  end)

  it("hides while an item is being recrafted: a recraft is never priced as a fresh craft", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, recraft = true, allocations = {} } })
    VALUES[103], VALUES[900] = commodity(400), commodity(10000)
    assert.is_false(show():IsShown())
  end)

  it("grows with its text, every line wrapped in the strip", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
    VALUES[103], VALUES[900] = commodity(400), commodity(10000)
    local f = show()
    local short = f:GetHeight()
    for _, line in ipairs(f.lines) do assert.is_true(W.state(line).wordWrap) end
    GC.L = setmetatable({}, { __index = function(_, key) return key .. " " .. string.rep("lang ", 40) end })
    S.Refresh()
    assert.is_true(f:GetHeight() > short)
    for _, line in ipairs(f.lines) do assert.is_nil(W.state(line).maxLines) end
  end)

  it("sits under the lowest shown reagent block, and under Auctionator's strip when it shows", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
    VALUES[103], VALUES[900] = commodity(400), commodity(10000)
    local form = TS.form
    -- Region:GetBottom, in screen units: lower on screen is smaller.
    function form.Reagents:GetBottom() return 300 end
    function form.OptionalReagents:GetBottom() return 200 end
    local recraft = form.extraSlotFrames[1]
    function recraft:GetBottom() return 500 end
    recraft:Show()
    local f = show()
    assert.equal(form, f:GetParent())
    local _, relative = f:GetPoint(1)
    assert.equal(form.OptionalReagents, relative)
    form.OptionalReagents:Hide()
    S.Refresh()
    _, relative = f:GetPoint(1)
    assert.equal(form.Reagents, relative)
    _G.AuctionatorCraftingInfoProfessionsFrame = W.CreateFrame("Frame")
    S.Refresh()
    _, relative = f:GetPoint(1)
    assert.equal(_G.AuctionatorCraftingInfoProfessionsFrame, relative)
    _G.AuctionatorCraftingInfoProfessionsFrame:Hide()
    S.Refresh()
    _, relative = f:GetPoint(1)
    assert.equal(form.Reagents, relative)
  end)

  it("attaches one frame after TRADE_SKILL_SHOW, once", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
    local ev = S._events
    assert.is_true(ev:IsEventRegistered("TRADE_SKILL_SHOW"))
    ev:GetScript("OnEvent")(ev, "TRADE_SKILL_SHOW")
    -- Blizzard's own TRADE_SKILL_SHOW handler loads the profession window: a frame later, it is there.
    assert.is_nil(S._frame)
    TS.runTimers()
    local f = S._frame
    assert.is_not_nil(f)
    ev:GetScript("OnEvent")(ev, "TRADE_SKILL_SHOW")
    TS.runTimers()
    assert.equal(f, S._frame)
    local events = {}
    for _, c in ipairs(TS.callsOf("RegisterCallback")) do
      events[#events + 1] = c.args[1]
      assert.equal(S, c.args[2])
    end
    table.sort(events)
    assert.same({ "Professions.AllocationUpdated", "Professions.ProfessionSelected", "Professions.TransactionUpdated",
      "ProfessionsRecipeListMixin.Event.OnRecipeSelected" }, events)
  end)

  it("repaints once however many callbacks fire in a frame", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
    show()
    assert.equal(0, #TS.timers)
    TS.trigger("Professions.AllocationUpdated")
    TS.trigger("Professions.TransactionUpdated")
    TS.trigger("ProfessionsRecipeListMixin.Event.OnRecipeSelected")
    assert.equal(1, #TS.timers)
    TS.runTimers()
    TS.trigger("Professions.AllocationUpdated")
    assert.equal(1, #TS.timers)
  end)

  it("never hooks or replaces Blizzard's frames", function()
    local file = assert(io.open("GoldCap/UI/CraftStrip.lua", "r"))
    local src = file:read("*a"):gsub("%-%-[^\n]*", "")
    file:close()
    assert.is_nil(src:find("hooksecurefunc", 1, true))
    assert.is_nil(src:find("HookScript", 1, true))
    for receiver in src:gmatch("([%w_%.]+):SetScript%(") do
      assert.equal("events", receiver)
    end
    assert.is_nil(src:find("ProfessionsFrame[%w_%.]*%s*=[^=]"))
    assert.is_nil(src:find("form%.[%w_]+%s*=[^=]"))
    assert.is_nil(src:find("Reagents%.[%w_]+%s*=[^=]"))
  end)
end)
