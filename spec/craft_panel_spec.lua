local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local TS = require("spec.support.trade_skill")

-- UI/CraftPanel.lua: GoldCap's panel beside the profession window, as the owner approved it
-- (canvas version 17). The header with the open profession, This recipe with its three figures,
-- the Worth crafting and Queue tabs, and Worth crafting: the character's known recipes of the open
-- profession that make a profit, by profit per craft, each with its icon, the craft's math, the
-- profit, how fast it sells and a quick add; a recipe that makes no profit, and one GoldCap cannot
-- price, are counted, never listed. At the foot, where the prices come from.
describe("craft panel", function()
  local GC, P, K, restore, VALUES

  local function commodity(mv, sold)
    return { mv = mv, sold = sold, ts = 0, source = "import", kind = "region_commodity" }
  end

  -- Recipe id makes item 900 + id from one of item 100 + id; `schematic` adds to its schematic.
  local function recipe(id, name, extra, schematic)
    return { info = TS.info(id, name, extra),
      schematic = TS.schematic(id, 900 + id, { TS.slot(1, 1, TS.items(100 + id)) }, schematic) }
  end

  -- A, B and C at 900, 500 and 200 a craft (each sells for 1,900 after the cut), selling 12, an
  -- unknown number and half a time a day; D has no price for its reagent. Alchemy is open; A's
  -- flask is of the second crafting quality.
  local function world(opts)
    opts = opts or {}
    opts.recipes = opts.recipes or { [1] = recipe(1, "A"), [2] = recipe(2, "B"), [3] = recipe(3, "C"), [4] = recipe(4, "D") }
    opts.filtered = opts.filtered or { 3, 4, 1, 2 }
    opts.professionID = 2823
    if opts.professionName == nil then opts.professionName = "Alchemy" end
    if opts.professionTexture == nil then opts.professionTexture = 4620669 end
    opts.icons = opts.icons or { [901] = 5001, [902] = 5002, [903] = 5003, [904] = 5004 }
    opts.tiers = opts.tiers or { [901] = 2 }
    return opts
  end

  local function prices()
    VALUES[101], VALUES[102], VALUES[103] = commodity(1000), commodity(1400), commodity(1700)
    VALUES[901], VALUES[902], VALUES[903], VALUES[904] = commodity(2000, 12), commodity(2000), commodity(2000, 0.5), commodity(2000)
  end

  local function load(opts)
    restore = TS.install(world(opts))
    GC = TS.craftGC()
    K = GC.Kit.Tokens.color
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

  local function rgb(fs)
    local r, g, b = fs:GetTextColor()
    return { r, g, b }
  end

  local function same(c) return { c[1], c[2], c[3] } end

  local function ids()
    local out = {}
    for _, row in ipairs(P._rows) do out[#out + 1] = row.recipeID end
    return out
  end

  local function snapshot(id) return GC.CraftClient.Snapshot(id) end

  after_each(function()
    if restore then restore() end
    W.unknownEvents = {}
    W.CLIENT_METRICS = false
  end)

  it("opens beside the profession window on its recipes page, as tall as the window", function()
    load()
    local f = show()
    assert.equal(TS.page, f:GetParent())
    assert.same({ "TOPLEFT", TS.frame, "TOPRIGHT", 0, 0 }, { f:GetPoint(1) })
    assert.equal(320, f:GetWidth())
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

  describe("the header", function()
    it("says GoldCap and names the open profession with its icon in a chip at the right", function()
      load()
      local f = show()
      assert.equal("GoldCap", f.brand:GetText())
      assert.same({ "LEFT", f.header, "LEFT", 0, 0 }, { f.logo:GetPoint(1) })
      assert.equal(f.logo, select(2, f.brand:GetPoint(1)))
      local chip = f.profession
      assert.is_true(chip:IsShown())
      assert.equal("Alchemy", chip.text:GetText())
      assert.equal(4620669, W.state(chip.icon).file)
      assert.is_true(chip.icon:IsShown())
      -- Round, as the board draws it: through the mask Blizzard's portraits use.
      assert.equal("Interface\\CharacterFrame\\TempPortraitAlphaMask", W.state(chip.icon).mask)
      local point, relative, relativePoint = chip:GetPoint(1)
      assert.same({ "RIGHT", f.header, "RIGHT" }, { point, relative, relativePoint })
      -- As wide as its icon and its name: a name is never cut.
      assert.is_true(chip:GetWidth() >= chip.icon:GetWidth() + chip.text:GetUnboundedStringWidth())
    end)

    it("leaves the icon out when the client has none, and the chip when it names no profession", function()
      load({ professionTexture = false })
      local f = show()
      assert.is_true(f.profession:IsShown())
      assert.is_false(f.profession.icon:IsShown())
      restore()
      load({ professionName = "" })
      f = show()
      assert.is_false(f.profession:IsShown())
    end)
  end)

  describe("Worth crafting", function()
    it("ranks the recipes that make a profit with the icon, the math, the profit and the pace", function()
      load()
      prices()
      local f = show()
      assert.same({ 1, 2, 3 }, ids())
      local v = f.worth
      assert.equal(GC.Util.Upper(GC.L["Best profit a craft"]), v.heading:GetText())
      assert.equal(GC.L["reagents at their cheapest quality"], v.cheapest:GetText())
      local first, second, third = P._rows[1].widget, P._rows[2].widget, P._rows[3].widget
      assert.equal("A", first.name:GetText())
      assert.equal(GC.L["Costs %s, sells for %s"]:format(GC.Util.Money(1000), GC.Util.Money(1900)), first.math:GetText())
      assert.equal("+" .. GC.Util.Money(900), first.profit:GetText())
      assert.same(same(K.profit), rgb(first.profit))
      -- What the recipe makes: its icon, with its crafting quality top left where it has one.
      assert.equal(5001, W.state(first.slot.icon).file)
      assert.is_true(first.slot.pip:IsShown())
      assert.equal("Professions-Icon-Quality-Tier2-Small", W.state(first.slot.pip).atlas)
      assert.equal(5002, W.state(second.slot.icon).file)
      assert.is_false(second.slot.pip:IsShown())
      -- Crafted gear carries its quality on each copy's link, and a row has none in hand: the
      -- crafted-quality call is never asked for a bare id, whatever a client would answer.
      TS.opts.crafted = { [902] = 3 }
      P.Refresh()
      assert.is_false(second.slot.pip:IsShown())
      for _, call in ipairs(TS.callsOf("GetItemCraftedQualityByItemInfo")) do
        assert.is_not.equal("number", type(call.args[1]))
      end
      -- How fast it sells: green with how many a day, amber under one a day, nothing unknown.
      assert.is_true(first.pace:IsShown())
      assert.equal(GC.L["about %s a day"]:format("12"), first.pace.text:GetText())
      assert.same(same(K.profit), rgb(first.pace.text))
      assert.is_false(second.pace:IsShown())
      assert.is_true(third.pace:IsShown())
      assert.equal(GC.L["Slow seller"], third.pace.text:GetText())
      assert.same(same(K.warn), rgb(third.pace.text))
      -- Rows stack in that order, each under the one before, in the list's scroll.
      local _, above = third.frame:GetPoint(1)
      assert.equal(second.frame, above)
      assert.equal(v.content, first.frame:GetParent())
    end)

    it("says how many a day sell: rounded and grouped", function()
      load()
      prices()
      VALUES[901], VALUES[902], VALUES[903] = commodity(2000, 2.6), commodity(2000, 1234), commodity(2000, 1)
      show()
      local text = {}
      for _, row in ipairs(P._rows) do text[row.recipeID] = row.widget.pace.text:GetText() end
      assert.equal(GC.L["about %s a day"]:format("3"), text[1])
      assert.equal(GC.L["about %s a day"]:format(GC.Util.Grouped(1234)), text[2])
      assert.equal(GC.L["about %s a day"]:format("1"), text[3])
    end)

    it("says how many one craft makes when it makes more than one", function()
      load({ recipes = { [1] = recipe(1, "A", nil, { quantityMin = 5 }) }, filtered = { 1 } })
      VALUES[101], VALUES[901] = commodity(1000), commodity(2000)
      show()
      local sells = math.floor(2000 * 0.95) * 5
      assert.equal(GC.L["%d a craft. Costs %s, sells for %s"]:format(5, GC.Util.Money(1000), GC.Util.Money(sells)),
        P._rows[1].widget.math:GetText())
    end)

    it("counts under the list what makes no profit and what has no price, one and many", function()
      load()
      prices()
      local v = show().worth
      assert.is_false(v.unprofitable:IsShown())
      assert.is_true(v.unpriced:IsShown())
      assert.equal(GC.L["1 has no GoldCap price for a reagent or what it makes."], v.unpriced:GetText())
      assert.same({ "BOTTOMLEFT", v, "BOTTOMLEFT", 0, 0 }, { v.unpriced:GetPoint(1) })
      VALUES[102] = commodity(5000) -- B loses 3,100 a craft
      P.Refresh()
      assert.same({ 1, 3 }, ids())
      assert.is_true(v.unprofitable:IsShown())
      assert.equal(GC.L["1 more recipe makes no profit now."], v.unprofitable:GetText())
      -- Over the unpriced line, at the foot of the view.
      local _, relative = v.unprofitable:GetPoint(1)
      assert.equal(v.unpriced, relative)
      VALUES[103] = commodity(1900) -- C makes exactly 0
      P.Refresh()
      assert.equal(GC.L["%d more recipes make no profit now."]:format(2), v.unprofitable:GetText())
      VALUES[902] = nil -- B's flask has no price now
      P.Refresh()
      assert.equal(GC.L["%d have no GoldCap price for a reagent or what they make."]:format(2), v.unpriced:GetText())
      VALUES[902], VALUES[104] = commodity(2000), commodity(1900) -- B loses again, D makes 0
      P.Refresh()
      assert.is_false(v.unpriced:IsShown())
      assert.equal(GC.L["%d more recipes make no profit now."]:format(3), v.unprofitable:GetText())
      assert.same({ "BOTTOMLEFT", v, "BOTTOMLEFT", 0, 0 }, { v.unprofitable:GetPoint(1) })
    end)

    it("says no recipe makes a profit when every priced recipe loses, and no price when none is priced", function()
      load()
      prices()
      VALUES[101], VALUES[102], VALUES[103] = commodity(5000), commodity(5000), commodity(5000)
      local v = show().worth
      assert.same({}, P._rows)
      assert.is_true(v.empty:IsShown())
      assert.is_false(v.scroll:IsShown())
      assert.equal(GC.L["No recipe here makes a profit now"], v.empty:GetText())
      assert.is_false(v.unprofitable:IsShown()) -- the empty line says it already
      VALUES = {}
      P.Refresh()
      assert.equal(GC.L["No recipe here has a GoldCap price yet"], v.empty:GetText())
      assert.is_false(v.unprofitable:IsShown())
      prices()
      P.Refresh()
      assert.is_false(v.empty:IsShown())
      assert.is_true(v.scroll:IsShown())
    end)

    it("wraps a long German name in its row, never cuts it, and the row grows for it", function()
      local long = "Phiole der unerschütterlichen Konzentrationsfähigkeitssteigerungsmeisterschaft"
      load({ recipes = { [1] = recipe(1, long), [2] = recipe(2, "B") }, filtered = { 1, 2 } })
      for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
      GC.ActivateLocale("deDE")
      prices()
      show()
      local row, short = P._rows[1].widget, P._rows[2].widget
      assert.equal(long, row.name:GetText())
      for _, fs in ipairs({ row.name, row.math }) do
        assert.is_true(W.state(fs).wordWrap)
        assert.is_true(W.state(fs).nonSpaceWrap)
        assert.is_nil(W.state(fs).maxLines)
      end
      assert.is_true(row.name:GetStringHeight() > short.name:GetStringHeight())
      assert.is_true(row.frame:GetHeight() > short.frame:GetHeight())
      -- The pace chip is as wide as its words in German.
      assert.equal(GC.L["about %s a day"]:format("12"), row.pace.text:GetText())
      assert.is_true(row.pace:GetWidth() >= row.pace.text:GetUnboundedStringWidth())
      GC.ActivateLocale(nil)
    end)

    -- A profit or pace too wide to leave the name its least room: the two go under the name and
    -- its math, which take the row's whole width, so nothing runs under the column.
    it("puts the profit and the pace under a name they would leave too little room beside them", function()
      load()
      prices()
      VALUES[901] = commodity(2000, 123456789012)
      show()
      local wide, plain = P._rows[1].widget, P._rows[2].widget
      assert.equal(GC.L["about %s a day"]:format(GC.Util.Grouped(123456789012)), wide.pace.text:GetText())
      -- The row's text runs from right of the icon to left of the "+": 282 less 6 + 24 + 6 at the
      -- left and 6 + 18 + 6 at the right.
      assert.equal(216, wide.name:GetWidth())
      assert.equal(216, wide.math:GetWidth())
      assert.same({ "TOPLEFT", wide.math, "BOTTOMLEFT", 0, -2 }, { wide.profit:GetPoint(1) })
      assert.same({ "TOPLEFT", wide.profit, "BOTTOMLEFT", 0, -2 }, { wide.pace:GetPoint(1) })
      local textH = wide.name:GetStringHeight() + 2 + wide.math:GetStringHeight() + 2 + wide.profit:GetStringHeight() + 2 + 14
      assert.is_true(wide.frame:GetHeight() >= textH)
      -- A row whose column leaves room keeps it beside the name.
      assert.equal("TOPRIGHT", (plain.profit:GetPoint(1)))
      assert.is_true(plain.name:GetWidth() < 216)
    end)

    it("tints the row of the recipe open in Blizzard's window gold, with a gold border", function()
      load({ open = { recipeID = 2, allocations = {} } })
      prices()
      show()
      local open, other = P._rows[2].widget, P._rows[1].widget
      assert.same({ K.gold[1], K.gold[2], K.gold[3], 0.07 }, W.state(open.frame.fill).vertex)
      assert.same({ K.gold[1], K.gold[2], K.gold[3], 0.45 }, W.state(open.frame.ring).vertex)
      assert.same(K.glassTop, W.state(other.frame.fill).vertex)
      assert.same(K.hairline, W.state(other.frame.ring).vertex)
    end)

    it("opens a row's recipe in Blizzard's window on a left click, inside the click", function()
      load()
      prices()
      show()
      local row = P._rows[2].widget
      assert.same({ "LeftButtonUp", "RightButtonUp" }, W.state(row.frame).clicks)
      row.frame:GetScript("OnClick")(row.frame, "LeftButton")
      local calls = TS.callsOf("OpenRecipe")
      assert.equal(1, #calls)
      assert.same({ 2 }, calls[1].args)
      -- Nothing of it waits for a later frame.
      assert.equal(0, #TS.timers)
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

    it("never reprices Worth crafting for a bag change, a craft or another reagent picked", function()
      load({ open = { recipeID = 2, allocations = {} } })
      prices()
      show()
      local asked = #TS.callsOf("GetFilteredRecipeIDs")
      local ev = P._events
      ev:GetScript("OnEvent")(ev, "BAG_UPDATE_DELAYED")
      ev:GetScript("OnEvent")(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 2)
      TS.trigger("Professions.AllocationUpdated")
      TS.trigger("Professions.TransactionUpdated")
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

    it("scrolls inside the panel's height, between its heading and the lines under it", function()
      load()
      prices()
      local f = show()
      local v = f.worth
      assert.equal(f.body, v:GetParent())
      assert.equal(v.content, v.scroll:GetScrollChild())
      local top, on, _, _, below = v.scroll:GetPoint(1)
      assert.same({ "TOPLEFT", v }, { top, on })
      assert.is_true(-below > v.heading:GetStringHeight())
      local point, relative, _, _, y = v.scroll:GetPoint(2)
      assert.same({ "BOTTOMRIGHT", v }, { point, relative })
      assert.is_true(y >= v.unpriced:GetHeight())
    end)

    it("puts the heading's two parts side by side when they fit, else one under the other", function()
      -- Measured as the client draws a 9-point face (spec/support/wow_frames.lua).
      W.CLIENT_METRICS = true
      load()
      prices()
      local f = show()
      local v = f.worth
      local point, relative, relativePoint = v.cheapest:GetPoint(1)
      assert.same({ "TOPRIGHT", v, "TOPRIGHT" }, { point, relative, relativePoint })
      local listTop = select(5, v.scroll:GetPoint(1))
      -- Words too long to share the line: the second under the first, across the panel, and the
      -- list lower for it.
      GC.L = setmetatable({}, { __index = function(_, key) return key .. " " .. string.rep("w", 14) end })
      P.Refresh()
      point, relative, relativePoint = v.cheapest:GetPoint(1)
      assert.same({ "TOPLEFT", v.heading, "BOTTOMLEFT" }, { point, relative, relativePoint })
      assert.equal(320 - 2 * 11, v.heading:GetWidth())
      assert.equal(320 - 2 * 11, v.cheapest:GetWidth())
      assert.is_true(select(5, v.scroll:GetPoint(1)) < listTop)
    end)
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

    local function values(card)
      local out = {}
      for i, cell in ipairs(card.cells) do out[i] = cell.value:GetText() end
      return out
    end

    it("shows the open recipe with its icon, its quality and its three figures", function()
      local f = loadOpen({ open = { recipeID = 1, allocations = {} } })
      local card = f.card
      assert.is_true(card:IsShown())
      assert.equal(GC.Util.Upper(GC.L["This recipe"]), card.kicker:GetText())
      assert.equal("A", card.name:GetText())
      assert.is_true(W.state(card.name).wordWrap)
      assert.equal(5001, W.state(card.slot.icon).file)
      assert.equal("Professions-Icon-Quality-Tier2-Small", W.state(card.slot.pip).atlas)
      local labels = {}
      for i, cell in ipairs(card.cells) do labels[i] = cell.label:GetText() end
      assert.same({ GC.L["Reagents"], GC.L["Sells for, after cut"], GC.L["Profit a craft"] }, labels)
      assert.same({ GC.Util.Money(1000), GC.Util.Money(1900), "+" .. GC.Util.Money(900) }, values(card))
      assert.same(same(K.profit), rgb(card.cells[3].value))
      assert.same({ K.profit[1], K.profit[2], K.profit[3], 0.3 }, W.state(card.cells[3].ring).vertex)
      assert.is_false(card.missing:IsShown())
      assert.is_false(card.queued:IsShown())
      assert.equal(GC.L["Add to queue"], card.add.label)
      assert.equal(GC.L["Restock to"], card.restock.label)
      -- The tabs sit under the card, and the view under the tabs.
      local _, above = f.switch:GetPoint(1)
      assert.equal(card, above)
      _, above = f.body:GetPoint(1)
      assert.equal(f.switch, above)
    end)

    -- What this allocation makes comes with its link (GetRecipeOutputItemData's hyperlink): crafted
    -- gear's quality is asked with it.
    it("draws the quality of crafted gear the window says it makes, from that item's link", function()
      local link = "|cffa335ee|Hitem:902::::::::80:::::::::|h[B]|h|r"
      local f = loadOpen({ open = { recipeID = 2, allocations = {}, output = 902, link = link }, craftedLinks = { [link] = 3 } })
      assert.equal(5002, W.state(f.card.slot.icon).file)
      assert.is_true(f.card.slot.pip:IsShown())
      assert.equal("Professions-Icon-Quality-Tier3-Small", W.state(f.card.slot.pip).atlas)
    end)

    it("prices the reagents the player picked, and follows another pick", function()
      local f = loadOpen({ recipes = { [2] = { info = TS.info(2, "B"),
        schematic = TS.schematic(2, 902, { TS.slot(1, 1, TS.items(102, 112)) }) } }, filtered = { 2 } })
      VALUES[112] = commodity(1500)
      assert.same({ GC.Util.Money(1400), GC.Util.Money(1900), "+" .. GC.Util.Money(500) }, values(f.card))
      TS.opts.open.allocations = { [1] = { { itemID = 112, q = 1 } } }
      TS.trigger("Professions.AllocationUpdated")
      TS.runTimers()
      assert.same({ GC.Util.Money(1500), GC.Util.Money(1900), "+" .. GC.Util.Money(400) }, values(f.card))
    end)

    it("paints a loss in red, with no plus sign", function()
      local f = loadOpen()
      VALUES[102] = commodity(5000)
      P.Refresh()
      assert.equal(GC.Util.Money(-3100), f.card.cells[3].value:GetText())
      assert.same(same(K.loss), rgb(f.card.cells[3].value))
    end)

    it("names what has no price instead of figures, as the strip does", function()
      local f = loadOpen({ names = { [902] = "Flask B" } })
      VALUES[902] = nil
      P.Refresh()
      local card = f.card
      assert.is_true(card.missing:IsShown())
      assert.equal(GC.L["No GoldCap price for %s"]:format("Flask B"), card.missing:GetText())
      assert.is_true(W.state(card.missing).wordWrap)
      for _, cell in ipairs(card.cells) do assert.is_false(cell:IsShown()) end
      assert.is_true(card.add:IsShown())
    end)

    it("says how the queue holds the open recipe: crafts to make, or the target it restocks to", function()
      local f = loadOpen({ counts = { [902] = 5 } })
      local card, char = f.card, "Name-Realm"
      assert.is_false(card.queued:IsShown())
      GC.CraftQueue.Add(char, snapshot(2), 3)
      P.Refresh()
      assert.is_true(card.queued:IsShown())
      assert.equal(GC.L["In queue: %d"]:format(3), card.queued.text:GetText())
      assert.same(same(K.yours), rgb(card.queued.text))
      assert.is_true(card.queued:GetWidth() >= card.queued.text:GetUnboundedStringWidth())
      -- A restock says its target, whatever the bags hold: the Queue's line says how far along.
      GC.CraftQueue.Restock(char, snapshot(2), 12)
      P.Refresh()
      assert.equal(GC.L["Restock to %d"]:format(12), card.queued.text:GetText())
      assert.same(same(K.yours), rgb(card.queued.text))
      assert.is_true(card.queued:GetWidth() >= card.queued.text:GetUnboundedStringWidth())
      TS.opts.counts[902] = 20
      P.Refresh()
      assert.equal(GC.L["Restock to %d"]:format(12), card.queued.text:GetText())
      GC.CraftQueue.Remove(char, 2)
      P.Refresh()
      assert.is_false(card.queued:IsShown())
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
      assert.equal(0, #TS.callsOf("OpenRecipe"))
      local texts = {}
      for _, e in ipairs(entries) do if e.text then texts[#texts + 1] = e.text end end
      assert.same({ GC.Util.ClientText(GC.L["Add to queue"]), GC.Util.ClientText(GC.L["Restock to"]) }, texts)
      entries[#entries - 1].fn()
      commit("2")
      assert.equal(2, GC.CraftQueue.Entries("Name-Realm")[1].count)
      assert.equal(2, GC.CraftQueue.Entries("Name-Realm")[1].recipe.recipeID)
    end)

    it("adds one craft at once with a row's +, as Add to queue does, and the Queue tab counts it", function()
      local f = loadOpen()
      local changed = 0
      P.OnQueueChanged = function() changed = changed + 1 end
      local badge = f.switch.badge
      assert.is_false(badge:IsShown())
      local row = P._rows[2].widget
      assert.is_true(row.add:IsShown())
      assert.same({ GC.Theme.IconCoords("plus") }, W.state(row.add.glyph).texCoord)
      row.add:GetScript("OnClick")(row.add)
      local entries = GC.CraftQueue.Entries("Name-Realm")
      assert.equal(1, #entries)
      assert.equal(2, entries[1].recipe.recipeID)
      assert.equal(1, entries[1].count)
      -- At once: no question first.
      assert.is_falsy(editor() and editor():IsShown())
      assert.equal(1, changed)
      assert.equal(1, #TS.timers)
      TS.runTimers()
      assert.is_true(badge:IsShown())
      assert.equal("1", badge.text:GetText())
      assert.equal(GC.L["In queue: %d"]:format(1), f.card.queued.text:GetText())
      -- A second press adds to the same line.
      P._rows[2].widget.add:GetScript("OnClick")(P._rows[2].widget.add)
      TS.runTimers()
      assert.equal(2, GC.CraftQueue.Entries("Name-Realm")[1].count)
      assert.equal("1", badge.text:GetText())
      P._rows[1].widget.add:GetScript("OnClick")(P._rows[1].widget.add)
      TS.runTimers()
      assert.equal("2", badge.text:GetText())
    end)

    it("says on the + what a press does", function()
      loadOpen()
      local saved = _G.GameTooltip
      finally(function() _G.GameTooltip = saved end)
      local tip = {}
      _G.GameTooltip = {
        SetOwner = function(_, owner, anchor) tip.owner, tip.anchor = owner, anchor end,
        SetText = function(_, text) tip.text = text end,
        Show = function() tip.shown = true end,
        Hide = function() tip.shown = false end,
      }
      local add = P._rows[1].widget.add
      add:GetScript("OnEnter")(add)
      assert.equal(add, tip.owner)
      assert.equal(GC.Util.ClientText(GC.L["Add one craft to the queue"]), tip.text)
      assert.is_true(tip.shown)
      add:GetScript("OnLeave")(add)
      assert.is_false(tip.shown)
    end)

    it("offers no + and no buttons while the store is a newer GoldCap's, and keeps the figures", function()
      local f = loadOpen()
      GC.db.craft = { v = 2, chars = {} }
      P.Refresh()
      assert.is_true(f.card:IsShown())
      for _, cell in ipairs(f.card.cells) do assert.is_true(cell:IsShown()) end
      assert.is_false(f.card.add:IsShown())
      assert.is_false(f.card.restock:IsShown())
      for _, row in ipairs(P._rows) do assert.is_false(row.widget.add:IsShown()) end
    end)

    it("hides This recipe for a recipe GoldCap does not price", function()
      local f = loadOpen({ open = { recipeID = 9, allocations = {} },
        recipes = { [1] = recipe(1, "A"), [2] = recipe(2, "B"), [9] = recipe(9, "Salvage", { isSalvageRecipe = true }) },
        filtered = { 1, 2 } })
      assert.is_false(f.card:IsShown())
      local _, above = f.switch:GetPoint(1)
      assert.equal(f.header, above)
    end)

    it("shows an unlearned recipe's figures without a way to queue it", function()
      -- Blizzard's list shows unlearned recipes too, and selecting one fills the form.
      local f = loadOpen({ open = { recipeID = 9, allocations = {} },
        recipes = { [1] = recipe(1, "A"), [2] = recipe(2, "B"), [9] = recipe(9, "Unlearned", { learned = false }) },
        filtered = { 1, 2, 9 } })
      VALUES[109], VALUES[909] = commodity(1000), commodity(2000)
      P.Refresh()
      assert.is_true(f.card:IsShown())
      assert.equal("Unlearned", f.card.name:GetText())
      assert.same({ GC.Util.Money(1000), GC.Util.Money(1900), "+" .. GC.Util.Money(900) }, values(f.card))
      assert.is_false(f.card.add:IsShown())
      assert.is_false(f.card.restock:IsShown())
      assert.is_nil(f.card.recipe)
    end)

    it("sizes the two buttons to their words and glyphs in every locale, one under the other when they do not fit", function()
      local f = loadOpen()
      for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
      local inner = f.card:GetWidth() - 2 * 8
      local besideSomewhere = false
      for _, code in ipairs(helper.localeCodes()) do
        GC.ActivateLocale(code)
        P.Refresh()
        local add, restock = f.card.add, f.card.restock
        for _, b in ipairs({ add, restock }) do
          assert.is_true(b:GetWidth() >= b.glyph:GetWidth() + b.text:GetUnboundedStringWidth(), code .. ": " .. tostring(b.label))
          assert.is_true(b:GetWidth() <= inner, code .. ": " .. tostring(b.label))
          -- The glyph, then the words, centred together.
          local _, on, _, glyphX = b.glyph:GetPoint(1)
          local _, textOn, _, textX = b.text:GetPoint(1)
          assert.same({ b, b }, { on, textOn }, code)
          assert.is_true(textX > glyphX + b.glyph:GetWidth(), code)
          local right = b:GetWidth() - (textX + b.text:GetUnboundedStringWidth())
          assert.is_true(math.abs(glyphX - right) <= 1, code)
        end
        assert.equal(add:GetWidth(), restock:GetWidth(), code)
        local point, relative, relativePoint = restock:GetPoint(1)
        assert.equal(add, relative, code)
        if add:GetWidth() == inner then
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

  describe("the tabs", function()
    it("switch between Worth crafting and the Queue, the one on screen filled gold", function()
      load()
      prices()
      local f = show()
      local sw = f.switch
      assert.equal(GC.L["Worth crafting"], sw.worth.label)
      assert.equal(GC.L["Queue"], sw.queue.label)
      assert.same(same(K.onGold), rgb(sw.worth.text))
      assert.same(same(K.text3), rgb(sw.queue.text))
      for _, b in ipairs({ sw.worth, sw.queue }) do
        assert.is_true(b:GetWidth() >= b.text:GetUnboundedStringWidth())
      end
      -- Each half of the track: the two fill the panel's width.
      assert.equal(sw.worth:GetWidth(), sw.queue:GetWidth())
      assert.equal(320 - 2 * 11, sw:GetWidth())
      local beside = sw:GetHeight()
      -- Words too long for half the track: one tab under the other, each across it.
      GC.L = setmetatable({}, { __index = function(_, key) return key .. " " .. string.rep("w", 14) end })
      P.Refresh()
      local point, relative, relativePoint = sw.queue:GetPoint(1)
      assert.same({ "TOPLEFT", sw.worth, "BOTTOMLEFT" }, { point, relative, relativePoint })
      assert.equal(320 - 2 * 11 - 2 * 2, sw.worth:GetWidth())
      assert.equal(sw.worth:GetWidth(), sw.queue:GetWidth())
      for _, b in ipairs({ sw.worth, sw.queue }) do
        assert.is_true(b:GetWidth() >= b.text:GetUnboundedStringWidth())
      end
      assert.is_true(sw:GetHeight() > beside)
    end)

    it("count the queue's lines on the Queue tab, and follow a finished craft", function()
      load({ open = { recipeID = 2, allocations = {} }, counts = { [902] = 5 } })
      prices()
      local char = "Name-Realm"
      GC.CraftQueue.Add(char, snapshot(2), 1)
      GC.CraftQueue.Restock(char, snapshot(1), 12)
      local f = show()
      local badge = f.switch.badge
      assert.equal("2", badge.text:GetText())
      assert.is_true(badge:GetWidth() >= badge.text:GetUnboundedStringWidth())
      -- The badge sits right of the tab's words.
      local _, left = badge:GetPoint(1)
      assert.equal(f.switch.queue, left)
      assert.equal(GC.L["In queue: %d"]:format(1), f.card.queued.text:GetText())
      -- The craft finishes (UI/CraftQueueView.lua takes it off the queue on this event).
      GC.CraftQueue.OnCraftSucceeded(char, 2)
      local ev = P._events
      ev:GetScript("OnEvent")(ev, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 2)
      TS.runTimers()
      assert.equal("1", badge.text:GetText())
      assert.is_false(f.card.queued:IsShown())
    end)

    it("keep a count of two or three figures clear of the badge's edges", function()
      -- A chip bounds its words 4px in from each side and cuts what does not fit: the count is
      -- centred in the badge on its own instead, as wide as its figures, with room either side.
      local recipes, filtered = {}, {}
      for id = 1, 12 do
        recipes[id] = recipe(id, "R" .. id)
        filtered[id] = id
      end
      load({ recipes = recipes, filtered = filtered })
      prices()
      for id = 1, 12 do GC.CraftQueue.Add("Name-Realm", snapshot(id), 1) end
      local badge = show().switch.badge
      assert.equal("12", badge.text:GetText())
      assert.equal(1, badge.text:GetNumPoints())
      assert.same({ "CENTER", badge, "CENTER", 0, 0 }, { badge.text:GetPoint(1) })
      assert.is_true(badge:GetWidth() >= badge.text:GetUnboundedStringWidth() + 2 * 4)
    end)
  end)

  describe("the foot", function()
    it("says where the prices come from and how old they are, under a dot in their colour", function()
      load()
      prices()
      GC.Data.OriginState = function() return "app" end
      GC.db.imported = { ts = time() - 720 }
      local f = show()
      local text, fresh = GC.HoardFrame.Footer.PricesNow()
      assert.equal(text, f.prices:GetText())
      assert.is_true(fresh)
      assert.same({ K.profit[1], K.profit[2], K.profit[3], 1 }, W.state(f.dot).vertex)
      assert.is_true(W.state(f.prices).wordWrap)
      local point, relative, relativePoint = f.prices:GetPoint(1)
      assert.same({ "BOTTOMLEFT", f, "BOTTOMLEFT" }, { point, relative, relativePoint })
      GC.db.imported.ts = time() - 3 * 3600
      P.Refresh()
      assert.same({ K.warn[1], K.warn[2], K.warn[3], 1 }, W.state(f.dot).vertex)
      -- The view ends above it.
      local _, _, _, _, y = f.body:GetPoint(2)
      assert.is_true(y > f.prices:GetHeight())
    end)
  end)

  it("leaves the list room for three rows under the tallest top it can have", function()
    -- A long name, every word long enough to wrap or stack: This recipe's buttons one under the
    -- other, the tabs one under the other, the heading's two parts too, and the price line wrapped,
    -- measured as the client draws each face's size (spec/support/wow_frames.lua).
    W.CLIENT_METRICS = true
    local long = "Phiole der unerschütterlichen Konzentrationsfähigkeitssteigerungsmeisterschaft"
    load({ open = { recipeID = 1, allocations = {} },
      recipes = { [1] = recipe(1, long), [2] = recipe(2, "B"), [3] = recipe(3, "C"), [4] = recipe(4, "D") } })
    prices()
    local f = show()
    GC.L = setmetatable({}, { __index = function(_, key) return key .. " " .. string.rep("w", 14) end })
    P.Refresh()
    local _, above = f.card.restock:GetPoint(1)
    assert.equal(f.card.add, above)
    _, above = f.switch.queue:GetPoint(1)
    assert.equal(f.switch.worth, above)
    local function down(region) return -select(5, region:GetPoint(1)) end
    local top = down(f.header) + f.header:GetHeight() + down(f.card) + f.card:GetHeight() + down(f.switch)
      + f.switch:GetHeight() + down(f.body)
    local body = f:GetHeight() - top - select(5, f.body:GetPoint(2))
    local v = f.worth
    local listTop = -select(5, v.scroll:GetPoint(1))
    local listFoot = select(5, v.scroll:GetPoint(2))
    local rows = 0
    for i = 1, 3 do rows = rows + P._rows[i].widget.frame:GetHeight() + (i > 1 and 3 or 0) end
    assert.is_true(body - listTop - listFoot >= rows, ("%s left for %s"):format(body - listTop - listFoot, rows))
  end)

  describe("coming back", function()
    -- docs/addon/AGENTS.md "Text": a one-line label whose frame or a parent was hidden and shown
    -- again can come back blank, and SetText with the text it holds does not redraw it. The cure
    -- is clear, set, hide, show, on every re-show. The recipes page hides on every close and tab.
    local function watch(logs, fs)
      local log = {}
      local set, hide, showIt = fs.SetText, fs.Hide, fs.Show
      fs.SetText = function(self, text, ...)
        log[#log + 1] = "set " .. tostring(text)
        return set(self, text, ...)
      end
      fs.Hide = function(self) log[#log + 1] = "hide"; return hide(self) end
      fs.Show = function(self) log[#log + 1] = "show"; return showIt(self) end
      logs[fs] = log
    end

    local function restamped(logs, fs)
      local log, n = logs[fs], #logs[fs]
      return n >= 4 and log[n - 3] == "set " and log[n - 2] == "set " .. tostring(fs:GetText()) and log[n - 1] == "hide"
        and log[n] == "show"
    end

    local function watchAll(logs, owners)
      for _, owner in ipairs(owners) do
        for _, fs in ipairs(owner.texts or {}) do watch(logs, fs) end
      end
    end

    it("redraws every line it shows when the recipes page shows again, then repaints what changed", function()
      load({ open = { recipeID = 2, allocations = {} } })
      prices()
      local f = show()
      local first = P._rows[1].widget
      local logs = {}
      local owners = { f, f.worth }
      for _, row in ipairs(f.worth.rows) do owners[#owners + 1] = row end
      watchAll(logs, owners)
      -- Each named one is among them.
      for _, fs in ipairs({ f.brand, f.profession.text, f.card.kicker, f.card.name, f.card.queued.text,
        f.card.cells[1].label, f.card.cells[3].value, f.card.add.text, f.card.restock.text, f.switch.worth.text,
        f.switch.queue.text, f.switch.badge.text, f.worth.heading, f.worth.cheapest, f.prices, first.name, first.math,
        first.profit, first.pace.text }) do
        assert.is_truthy(logs[fs])
      end
      -- Away, the queue changes (a craft from the Orders page): the panel reads nothing meanwhile.
      TS.page:Hide()
      GC.CraftQueue.Add("Name-Realm", snapshot(2), 2)
      TS.page:Show()
      -- The client runs the panel's OnShow as its page shows again.
      f:GetScript("OnShow")(f)
      local checked = 0
      for fs in pairs(logs) do
        if fs:IsShown() and fs:GetText() ~= nil then
          assert.is_true(restamped(logs, fs), tostring(fs:GetText()))
          checked = checked + 1
        end
      end
      assert.is_true(checked >= 18)
      -- And one repaint on the next frame: the Queue's count and This recipe's chip as they are now.
      assert.equal(1, #TS.timers)
      TS.runTimers()
      assert.equal("1", f.switch.badge.text:GetText())
      assert.equal(GC.L["In queue: %d"]:format(2), f.card.queued.text:GetText())
    end)

    it("asks for no second repaint when its own repaint shows it", function()
      load({ external = { guild = true } })
      prices()
      local f = show()
      assert.is_false(f:IsShown())
      TS.opts.external = {}
      local shows = 0
      local onShow = f:GetScript("OnShow")
      local showIt = f.Show
      f.Show = function(self)
        shows = shows + 1
        showIt(self)
        onShow(self)
      end
      P.Refresh()
      assert.equal(1, shows)
      assert.equal(0, #TS.timers)
    end)

    it("redraws Worth crafting when its tab is picked again, and a row the list shows again", function()
      load()
      prices()
      GC.CraftQueueView = {
        Build = function(host) GC.CraftQueueView._frame = W.CreateFrame("Frame", nil, host) end,
        Refresh = function() end,
      }
      local f = show()
      local v = f.worth
      f.switch.queue:GetScript("OnClick")(f.switch.queue)
      assert.is_false(v:IsShown())
      local logs = {}
      local owners = { v }
      for _, row in ipairs(v.rows) do owners[#owners + 1] = row end
      watchAll(logs, owners)
      f.switch.worth:GetScript("OnClick")(f.switch.worth)
      assert.is_true(v:IsShown())
      for _, fs in ipairs({ v.heading, v.cheapest, P._rows[1].widget.name, P._rows[1].widget.profit }) do
        assert.is_true(restamped(logs, fs), tostring(fs:GetText()))
      end
      -- A row a shorter list hid, shown again by a longer one.
      TS.opts.filtered = { 1 }
      P.Refresh()
      local row = v.rows[2]
      assert.is_false(row.frame:IsShown())
      watch(logs, row.name)
      TS.opts.filtered = { 1, 2 }
      P.Refresh()
      assert.is_true(row.frame:IsShown())
      assert.is_true(restamped(logs, row.name))
    end)
  end)

  it("registers each event through pcall, and a cast for the player alone", function()
    W.unknownEvents = { NEW_RECIPE_LEARNED = true }
    load()
    local ev = P._events
    assert.is_false(ev:IsEventRegistered("NEW_RECIPE_LEARNED"))
    for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "BAG_UPDATE_DELAYED", "UNIT_SPELLCAST_SUCCEEDED" }) do
      assert.is_true(ev:IsEventRegistered(event), event)
    end
    assert.same({ "player" }, W.state(ev).unitEvents.UNIT_SPELLCAST_SUCCEEDED)
    local file = assert(io.open("GoldCap/UI/CraftPanel.lua", "r"))
    local src = file:read("*a"):gsub("%-%-[^\n]*", "")
    file:close()
    assert.is_nil(src:find(":RegisterEvent%("))
    assert.is_nil(src:find(":RegisterUnitEvent%("))
    assert.is_truthy(src:find("pcall%(events%.RegisterEvent, events,"))
    assert.is_truthy(src:find('pcall%(events%.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player"%)'))
    assert.is_nil(src:find("hooksecurefunc", 1, true))
  end)
end)
