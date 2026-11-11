local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local TS = require("spec.support.trade_skill")
local Merchant = require("spec.support.merchant")

-- WoW: Forever's crafting panel: retail's panel, loaded as GoldCap_Camelot.toc loads it (none of
-- the Hoard's files) with Forever's two files after the ones they change
-- (Services/CraftClient_Camelot.lua, UI/CraftPanel_Camelot.lua). Prices are Forever's scans
-- (GC.Data.GetItemValue answers source "scan"), a vendor's reagent is priced at what a merchant asked
-- the player (Core/ForeverVendorPrices.lua), a book under 20 units prices nothing, and nothing says
-- how many sell a day.
describe("Forever craft panel", function()
  local GC, P, CC, restore, restoreMerchant, VALUES, ROOT, FOLD, PAYLOAD, BUY_LIST

  -- A Forever price: a scan of what is listed, the player's own or every player's, of 40 units
  -- unless `extra` says otherwise.
  local function scan(mv, extra)
    local v = { mv = mv, ts = 0, source = "scan", kind = "own_scan", currentQty = 40 }
    for k, x in pairs(extra or {}) do v[k] = x end
    return v
  end

  -- Recipe id makes item 900 + id from `slots`, by default one of item 100 + id.
  local function recipe(id, name, slots)
    return { info = TS.info(id, name), schematic = TS.schematic(id, 900 + id, slots or { TS.slot(1, 1, TS.items(100 + id)) }) }
  end

  -- Tailoring is open. 2320 (Coarse Thread) and 2324 are trade goods, 159 (water) is not.
  local function load(opts)
    opts = opts or {}
    opts.recipes = opts.recipes or { [1] = recipe(1, "Linen Bag", { TS.slot(1, 3, TS.items(2589)), TS.slot(2, 1, TS.items(2320)) }) }
    opts.filtered = opts.filtered or { 1 }
    opts.professionID = 2540
    opts.professionName = "Tailoring"
    opts.names = opts.names or { [2320] = "Coarse Thread", [901] = "Linen Bag", [2589] = "Linen Cloth" }
    opts.classes = opts.classes or { [2320] = 7, [2324] = 7, [2589] = 7, [159] = 0, [901] = 1 }
    restore = TS.install(opts)
    GC = TS.craftGCForever()
    VALUES, ROOT, FOLD, PAYLOAD, BUY_LIST = {}, {}, nil, nil, {}
    GC.Data = {
      GetItemValue = function(id) return VALUES[id] end,
      ForeverPayload = function() return PAYLOAD end,
    }
    GC.ForeverScan = { Root = function() return ROOT end, Fold = function() return FOLD end }
    GC.AppRuns = { VendorUnitFor = function(id) return BUY_LIST[id] end }
    GC.Ledger = { Context = function() return { char = "Name-Realm" } end }
    GC.db = {}
    for _, path in ipairs({ "UI/CraftPanel.lua", "UI/CraftQueueView.lua", "UI/CraftPanel_Camelot.lua" }) do
      helper.loadModule(path, GC)
    end
    P, CC = GC.CraftPanel, GC.CraftClient
  end

  local function show()
    local ev = P._events
    ev:GetScript("OnEvent")(ev, "TRADE_SKILL_SHOW")
    TS.runTimers()
    return P._frame
  end

  -- Linen Cloth at 50c on the auction house; the bag sells for 2,000c there.
  local function prices()
    VALUES[2589], VALUES[901] = scan(50), scan(2000)
  end

  after_each(function()
    if restoreMerchant then restoreMerchant() end
    restoreMerchant = nil
    if restore then restore() end
  end)

  it("draws without any of the Hoard's files, which Forever does not load", function()
    load()
    prices()
    ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
    local f = show()
    assert.is_nil(GC.HoardFrame)
    assert.is_true(f:IsShown())
    assert.equal("GoldCap", f.brand:GetText())
    assert.equal(1, #P._rows)
    assert.equal("Linen Bag", P._rows[1].widget.name:GetText())
  end)

  -- Forever's window hangs its book tab and a tab per profession off its right edge
  -- (Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml): the panel stands past them.
  it("stands right of the profession tabs Forever's window hangs at its edge", function()
    load()
    local tab = W.CreateFrame("Frame", nil, TS.frame)
    tab:SetSize(43, 51)
    TS.frame.ProfessionsOverviewTab = tab
    assert.same({ "TOPLEFT", TS.frame, "TOPRIGHT", 43, 0 }, { show():GetPoint(1) })
  end)

  it("stands at the window's edge when it hangs no tabs there", function()
    load()
    assert.same({ "TOPLEFT", TS.frame, "TOPRIGHT", 0, 0 }, { show():GetPoint(1) })
  end)

  describe("a vendor's reagent", function()
    -- Where one Coarse Thread's price comes from, in order: what a merchant asked the player, a BUY
    -- list's vendor price, the auction house's.
    local ORDER = {
      { name = "a merchant's price first", merchant = 10, list = 12, ah = 40, unit = 10 },
      { name = "a BUY list's vendor price with no merchant seen", list = 12, ah = 40, unit = 12 },
      { name = "the auction house with neither", ah = 40, unit = 40 },
      { name = "no price at all with none of them", unit = nil },
      { name = "a merchant's price over a book of two units", merchant = 10, ah = 40, qty = 2, unit = 10 },
      { name = "no price from a book of two units with no vendor's", ah = 40, qty = 2, unit = nil },
    }
    for _, case in ipairs(ORDER) do
      it("costs " .. case.name, function()
        load()
        if case.merchant then ROOT.foreverVendor = { v = 1, items = { [2320] = { u = case.merchant, at = 1 } } } end
        BUY_LIST[2320] = case.list
        VALUES[2320] = case.ah and scan(case.ah, { currentQty = case.qty }) or nil
        assert.equal(case.unit, CC.UnitOf(2320))
        assert.equal(case.merchant or case.list, CC.VendorOf(2320))
      end)
    end

    it("prices the recipe's reagents with it: three cloth at 50c and the thread at 10c", function()
      load()
      prices()
      ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
      show()
      local row = P._rows[1]
      assert.same({ cost = 160, sells = 1900, profit = 1740 }, row.result)
      assert.equal(GC.L["Costs %s, sells for %s"]:format(GC.Util.Money(160), GC.Util.Money(1900)), row.widget.math:GetText())
    end)

    it("is kept when the player opens a merchant that sells it, and nothing else that merchant sells", function()
      load()
      restoreMerchant = Merchant.install({
        { itemID = 2320, price = 10, stackCount = 1 },
        { itemID = 159, price = 25, stackCount = 1 },
        { itemID = 2324, price = 25, stackCount = 1, hasExtendedCost = true },
      })
      local ev = CC._merchantEvents
      ev:GetScript("OnEvent")(ev, "MERCHANT_SHOW")
      ev:GetScript("OnEvent")(ev, "MERCHANT_UPDATE")
      assert.is_nil(ROOT.foreverVendor) -- read a frame later, once for both
      TS.runTimers()
      assert.equal(10, CC.VendorOf(2320))
      assert.is_nil(CC.VendorOf(159))
      assert.is_nil(CC.VendorOf(2324))
      assert.same({ [2320] = true }, (function()
        local out = {}
        for id in pairs(ROOT.foreverVendor.items) do out[id] = true end
        return out
      end)())
    end)

    it("registers the merchant's events through pcall, as the panel's own", function()
      load()
      local state = W.state(CC._merchantEvents)
      assert.is_true(state.events.MERCHANT_SHOW)
      assert.is_true(state.events.MERCHANT_UPDATE)
    end)

    it("gives the recipe no figure while nothing prices it, counts it, and This recipe says how a merchant does", function()
      load({ open = { recipeID = 1, allocations = {} } })
      prices()
      local f = show()
      assert.equal(0, #P._rows)
      assert.equal(GC.L["1 has no GoldCap price for a reagent or what it makes."], f.worth.unpriced:GetText())
      local card = f.card
      assert.is_true(card.missing:IsShown())
      assert.equal(GC.L["No GoldCap price for %s"]:format("Coarse Thread") .. " "
        .. GC.L["A reagent a vendor sells gets its price once you open that vendor."], card.missing:GetText())
      for _, cell in ipairs(card.cells) do assert.is_false(cell:IsShown()) end
    end)

    it("says nothing of a merchant when only what the recipe makes has no price", function()
      load({ open = { recipeID = 1, allocations = {} } })
      prices()
      VALUES[901] = nil
      ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
      local card = show().card
      assert.equal(GC.L["No GoldCap price for %s"]:format("Linen Bag") .. " "
        .. GC.L["Sell for at least %s each to break even."]:format(GC.Util.Money(GC.CraftMath.Breakeven(160, 1))), card.missing:GetText())
    end)
  end)

  -- Under 20 units listed (Core/ForeverDeals.lua's MARKET_MIN_UNITS), the cheapest units are often
  -- asks nobody pays: a crowd value of 79s98 came from two units (owner, 2026-11-07).
  describe("a thin book", function()
    local LISTED = {
      { name = "prices from 20 units listed", qty = 20, cost = 50, sells = 2000 },
      { name = "prices nothing from 19", qty = 19 },
      { name = "prices nothing from a scan that counted no units", qty = "none" },
    }
    for _, case in ipairs(LISTED) do
      it(case.name .. ", for a reagent and for what a recipe makes", function()
        load()
        VALUES[2589], VALUES[901] = scan(50), scan(2000)
        local qty = case.qty ~= "none" and case.qty or nil
        VALUES[2589].currentQty, VALUES[901].currentQty = qty, qty
        assert.equal(case.cost, CC.UnitOf(2589))
        assert.equal(case.sells, CC.SellOf(901))
      end)
    end
  end)

  describe("a missing price in This recipe", function()
    -- Each case after Linen Cloth at 50c, the bag at 2,000c and thread seen at a merchant for 10c:
    -- what it changes, and whether the result names a merchant visit and a thin book.
    local CASES = {
      { name = "names a merchant for a trade good the recipe uses that no merchant was seen selling",
        set = function() ROOT.foreverVendor = nil end, vendorHint = true },
      { name = "names no merchant when only what it makes is missing, a trade good itself",
        classes = { [901] = 7 }, set = function() VALUES[901] = nil end },
      { name = "names no merchant for a missing reagent that is no crafting reagent",
        slots = { TS.slot(1, 3, TS.items(2589)), TS.slot(2, 1, TS.items(159)) } },
      { name = "names no merchant for the item the window shows it making, a trade good",
        classes = { [905] = 7 }, open = { recipeID = 1, output = 905, allocations = {} } },
      { name = "names no merchant for the recipe's own item while the window shows another recipe",
        classes = { [901] = 7 }, open = { recipeID = 2, output = 905, allocations = {} },
        set = function() VALUES[901] = nil end },
      { name = "names a thin book and a merchant for a trade good from too few units",
        set = function() VALUES[2589].currentQty = 5 end, thin = true, vendorHint = true },
      { name = "names a thin book alone for what it makes from too few units",
        set = function() VALUES[901].currentQty = 5 end, thin = true },
    }
    for _, case in ipairs(CASES) do
      it(case.name, function()
        local classes = { [2320] = 7, [2324] = 7, [2589] = 7, [159] = 0, [901] = 1, [905] = 1 }
        for id, class in pairs(case.classes or {}) do classes[id] = class end
        load({ classes = classes,
          recipes = case.slots and { [1] = recipe(1, "Linen Bag", case.slots) } or nil })
        prices()
        ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
        if case.set then case.set() end
        local result = CC.ProfitOf(CC.Snapshot(1), case.open)
        assert.is_table(result.missing)
        assert.equal(case.vendorHint, result.vendorHint)
        assert.equal(case.thin, result.thin)
      end)
    end

    it("says how many listed a price needs when the book was too thin", function()
      load({ open = { recipeID = 1, allocations = {} } })
      prices()
      VALUES[901].currentQty = 5
      ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
      local card = show().card
      assert.equal(GC.L["No GoldCap price for %s"]:format("Linen Bag") .. " "
        .. GC.L["An auction house price needs at least %d listed."]:format(20) .. " "
        .. GC.L["Sell for at least %s each to break even."]:format(GC.Util.Money(GC.CraftMath.Breakeven(160, 1))), card.missing:GetText())
    end)
  end)

  it("says the break-even price under its cells", function()
    load({ open = { recipeID = 1, allocations = {} } })
    prices()
    ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
    local card = show().card
    -- Linen Bag costs 3 x 50 + 10 = 160c.
    local want = GC.L["Sell for at least %s each to break even."]:format(GC.Util.Money(GC.CraftMath.Breakeven(160, 1)))
    assert.is_true(card.cells[1]:IsShown())
    assert.is_true(card.missing:IsShown())
    assert.equal(want, card.missing:GetText())
  end)

  it("an unpriced crafted item still gets its break-even price", function()
    load({ open = { recipeID = 1, allocations = {} } })
    prices()
    VALUES[901] = nil
    ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
    local sentence = GC.L["Sell for at least %s each to break even."]:format(GC.Util.Money(GC.CraftMath.Breakeven(160, 1)))
    local text = GC.CraftStrip.Lines(CC.ProfitOf(CC.Snapshot(1)))[1].text
    assert.equal(sentence, text:sub(-#sentence))
    assert.equal(text, show().card.missing:GetText())
  end)

  -- Owner, 2026-11-11: how many of it sell, on the craft's row. The site's sales tape of this
  -- auction house says (GC.Data.ForeverSales, units a day); the scan's own figures say nothing of
  -- what sells and are never read for it.
  it("says how many sell a day from the sales tape, slow under one, and nothing while there is no tape", function()
    load()
    prices()
    VALUES[901] = scan(2000, { sold = 12 })
    ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
    show()
    assert.is_false(P._rows[1].widget.pace:IsShown())
    assert.is_nil(P._rows[1].sold)
    assert.is_nil(select(2, CC.SellOf(901)))
    assert.equal(2000, CC.SellOf(901))

    local perDay = 37.4
    GC.Data.ForeverSales = function(id) return id == 901 and { units = 187, sales = 60, perDay = perDay, hours = 120 } or nil end
    P.Refresh()
    assert.same({ 2000, 37.4 }, { CC.SellOf(901) })
    assert.is_true(P._rows[1].widget.pace:IsShown())
    assert.equal(GC.L["about %s a day"]:format("37"), P._rows[1].widget.pace.text:GetText())
    -- The tape covered the item and nothing sold: a slow seller, said so.
    perDay = 0
    P.Refresh()
    assert.equal(GC.L["Slow seller"], P._rows[1].widget.pace.text:GetText())
  end)

  it("never builds the strip under the reagents: This recipe carries its three figures", function()
    load({ open = { recipeID = 1, allocations = {} } })
    prices()
    ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
    local ev = GC.CraftStrip._events
    ev:GetScript("OnEvent")(ev, "TRADE_SKILL_SHOW")
    local f = show()
    assert.is_nil(GC.CraftStrip._frame)
    assert.is_true(f.card.cells[1]:IsShown())
  end)

  describe("the price line", function()
    local NOW = 1000000
    -- Whose scans price the panel, and how old each is; fresh while the newest is under two hours.
    local LINES = {
      { name = "the player's own scan", own = NOW - 600, text = function(L) return L["Prices from your scan %s ago"]:format("10m") end, fresh = true },
      { name = "the Companion's crowd prices", crowd = NOW - 3 * 3600,
        text = function(L) return L["Prices from the Companion, %s ago"]:format("3h") end, fresh = false },
      { name = "both", own = NOW - 3 * 3600, crowd = NOW - 1200,
        text = function(L) return L["Prices from your scan %s ago and the Companion %s ago"]:format("3h", "20m") end, fresh = true },
      { name = "neither", text = function(L) return L["No scan of this auction house yet."] end, fresh = false },
    }
    for _, case in ipairs(LINES) do
      it("says where prices come from with " .. case.name, function()
        load()
        FOLD = case.own and { at = case.own, items = {} } or nil
        PAYLOAD = case.crowd and { ts = case.crowd, items = {} } or nil
        local text, fresh = P.PricesNow(NOW)
        assert.equal(case.text(GC.L), text)
        assert.equal(case.fresh, fresh)
      end)
    end

    it("is the line at the panel's foot, under a dot in its colour", function()
      load()
      prices()
      FOLD = { at = time() - 60, items = {} }
      local f = show()
      local K = GC.Kit.Tokens.color
      assert.equal(GC.L["Prices from your scan %s ago"]:format(GC.Util.FormatElapsedWords(60)), f.prices:GetText())
      assert.same({ K.profit[1], K.profit[2], K.profit[3], 1 }, W.state(f.dot).vertex)
      FOLD = nil
      P.Refresh()
      assert.equal(GC.L["No scan of this auction house yet."], f.prices:GetText())
      assert.same({ K.warn[1], K.warn[2], K.warn[3], 1 }, W.state(f.dot).vertex)
    end)
  end)
end)
