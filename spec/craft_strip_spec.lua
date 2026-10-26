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

  it("sits under the lowest shown block, Auctionator's strip, Finishing and Concentrate included", function()
    load({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
    VALUES[103], VALUES[900] = commodity(400), commodity(10000)
    local form = TS.form
    local f = show()
    assert.equal(form, f:GetParent())
    assert.is_true(f:IsShown())
    assert.same({ "TOPLEFT", form.OptionalReagents, "BOTTOMLEFT", 0, -8 }, { f:GetPoint(1) })
    form.OptionalReagents:Hide()
    S.Refresh()
    assert.same({ "TOPLEFT", form.Reagents, "BOTTOMLEFT", 0, -8 }, { f:GetPoint(1) })
    -- An extra slot laid out higher up is not the lowest.
    local recraft = form.extraSlotFrames[1]
    TS.layout(recraft, 328, 700, 180, 40)
    recraft:Show()
    S.Refresh()
    assert.same({ "TOPLEFT", form.Reagents, "BOTTOMLEFT", 0, -8 }, { f:GetPoint(1) })
    recraft:Hide()
    -- The small window: Finishing under Reagents, the Concentrate button 100 to its right.
    TS.layout(form.FinishingReagents, 328, 520, 180, 60)
    form.FinishingReagents:Show()
    TS.layout(form.Concentrate, 428, 540, 120, 40)
    form.Concentrate:Show()
    S.Refresh()
    assert.same({ "TOPLEFT", form.FinishingReagents, "BOTTOMLEFT", 0, -8 }, { f:GetPoint(1) })
    TS.layout(form.Concentrate, 428, 540, 120, 100)
    S.Refresh()
    -- Under the Concentrate button, and back at the reagents' left edge.
    assert.same({ "TOPLEFT", form.Concentrate, "BOTTOMLEFT", -100, -8 }, { f:GetPoint(1) })
    -- Auctionator's crafting strip hangs under the reagents (its own Mixins/Professions.lua).
    local auctionator = W.CreateFrame("Frame", nil, form)
    TS.layout(auctionator, 328, 430, 300, 32)
    _G.AuctionatorCraftingInfoProfessionsFrame = auctionator
    S.Refresh()
    assert.same({ "TOPLEFT", auctionator, "BOTTOMLEFT", 0, -8 }, { f:GetPoint(1) })
    auctionator:Hide()
    S.Refresh()
    assert.same({ "TOPLEFT", form.Concentrate, "BOTTOMLEFT", -100, -8 }, { f:GetPoint(1) })
  end)

  -- With no room under the reagents the strip hides: the panel's This recipe shows the same
  -- figures whether the strip shows or not (spec/craft_panel_spec.lua).
  describe("when there is no room under the reagents", function()
    local function priced(opts)
      load(opts)
      VALUES[101], VALUES[103], VALUES[900] = commodity(500), commodity(400), commodity(10000)
      return opts
    end

    -- A recipe with many slots: four rows of reagents, an optional row, down to just above the
    -- "Use Best Quality Reagents" checkbox (top at 293).
    local function crowd()
      TS.layout(TS.form.Reagents, 328, 650, 365, 220)
      TS.layout(TS.form.OptionalReagents, 328, 410, 180, 60)
    end

    it("draws nothing over Use Best Quality Reagents", function()
      priced({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
      crowd()
      assert.is_false(show():IsShown())
    end)

    it("hides in the small window when it would run past the form's bottom edge", function()
      priced({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
      -- Minimized: the form is 395 wide, no checkbox; Finishing under Reagents and the
      -- Concentrate button beside it reach down to 330, the form's bottom is at 247.
      TS.layout(TS.form, 300, 800, 395, 553)
      TS.form.AllocateBestQualityCheckbox:Hide()
      TS.form.OptionalReagents:Hide()
      TS.layout(TS.form.FinishingReagents, 328, 420, 180, 90)
      TS.form.FinishingReagents:Show()
      TS.layout(TS.form.Concentrate, 428, 440, 120, 110)
      TS.form.Concentrate:Show()
      local f = show()
      assert.is_false(f:IsShown())
      -- Without the Concentrate button and Finishing there is room under the reagents.
      TS.form.FinishingReagents:Hide()
      TS.form.Concentrate:Hide()
      S.Refresh()
      assert.is_true(f:IsShown())
    end)

    it("hides under Auctionator's strip when the two do not fit", function()
      priced({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
      local f = show()
      assert.is_true(f:IsShown())
      local auctionator = W.CreateFrame("Frame", nil, TS.form)
      TS.layout(auctionator, 328, 452, 300, 80)
      _G.AuctionatorCraftingInfoProfessionsFrame = auctionator
      S.Refresh()
      assert.is_false(f:IsShown())
    end)

    it("keeps clear of the Details column beside it, and hides when that leaves too little width", function()
      priced({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
      TS.layout(TS.form.Reagents, 328, 650, 365, 110)
      local f = show()
      assert.is_true(f:IsShown())
      -- Details reaches down to 375, below the strip's top: the strip ends 4 short of it.
      assert.equal(665 - 4 - 328, f:GetWidth())
      for _, line in ipairs(f.lines) do assert.equal(665 - 4 - 328 - 20, line:GetWidth()) end
      -- Details ending above the strip leaves it its full width.
      TS.layout(TS.form.Details, 665, 675, 263, 150)
      S.Refresh()
      assert.equal(360, f:GetWidth())
      TS.layout(TS.form.Details, 560, 675, 263, 300)
      S.Refresh()
      assert.is_false(f:IsShown())
    end)

    it("hides when the client has not laid the blocks out: it never draws over what it cannot see", function()
      priced({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
      function TS.form.OptionalReagents:GetBottom() return nil end
      assert.is_false(show():IsShown())
    end)

    it("repaints when the form changes size, as when the window is minimized", function()
      priced({ recipes = { [7] = potion() }, open = { recipeID = 7, allocations = {} } })
      show()
      local watch = S._watch
      assert.equal(TS.form, watch:GetParent())
      assert.equal(TS.form, W.state(watch).allPoints)
      assert.equal(0, #TS.timers)
      watch:GetScript("OnSizeChanged")(watch, 395, 553)
      assert.equal(1, #TS.timers)
    end)
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
    -- Scripts only on GoldCap's own frames: its event frame and the frame that watches the form's size.
    for receiver in src:gmatch("([%w_%.]+):SetScript%(") do
      assert.is_true(receiver == "events" or receiver == "watch", receiver)
    end
    assert.is_nil(src:find("ProfessionsFrame[%w_%.]*%s*=[^=]"))
    assert.is_nil(src:find("form%.[%w_]+%s*=[^=]"))
    assert.is_nil(src:find("Reagents%.[%w_]+%s*=[^=]"))
  end)
end)
