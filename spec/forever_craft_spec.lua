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
      assert.same({ 160, 1900, 1740 }, { row.result.cost, row.result.sells, row.result.profit })
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
  -- asks nobody pays: a crowd value of 79s98 came from two units (owner, 2026-11-07). A reagent
  -- keeps that rule.
  describe("a thin book of a reagent", function()
    local LISTED = {
      { name = "prices from 20 units listed", qty = 20, cost = 50 },
      { name = "prices nothing from 19", qty = 19 },
      { name = "prices nothing from a scan that counted no units", qty = "none" },
    }
    for _, case in ipairs(LISTED) do
      it(case.name, function()
        load()
        VALUES[2589] = scan(50)
        VALUES[2589].currentQty = case.qty ~= "none" and case.qty or nil
        assert.equal(case.cost, CC.UnitOf(2589))
      end)
    end
  end)

  -- What a crafted item sells for: what it sold for on its own house with 5 sales or more, else the
  -- site's median of the nearest markets (GCF1's E), never above a lot listed here now. Without E
  -- (an older site, or E dropped for size) or without a day of tape, the listings as before.
  describe("what a crafted item sells for", function()
    local function sold(n, extra)
      local s = { units = n, sales = n, perDay = n / 7, hours = 168 }
      for k, x in pairs(extra or {}) do s[k] = x end
      return s
    end
    local CASES = {
      { name = "no E, 20 listed or more: the listing, held to what it sold for", listed = { 2000, 25 },
        sales = sold(2, { median = 1800 }), unit = 1800, kind = "listings" },
      { name = "no E, 19 listed: nothing, from a thin book", listed = { 2000, 19 }, sales = sold(2, { median = 1800 }),
        kind = "listings", thin = true, noPace = true },
      { name = "no tape: the listing", listed = { 2000, 25 }, pool = { n = 5, items = {} }, unit = 2000, kind = "listings" },
      { name = "5 sales or more here: what it sells for now", listed = { 2600, 3 },
        sales = sold(6, { median = 2000, recent = 2400 }), pool = { n = 5, items = {} }, unit = 2400, kind = "own" },
      { name = "5 sales or more here and nothing listed: the median", sales = sold(6, { median = 2400 }),
        pool = { n = 5, items = {} }, unit = 2400, kind = "own" },
      { name = "5 sales or more here and a cheaper lot: the lot", listed = { 2000, 1 },
        sales = sold(6, { median = 2600, recent = 2400 }), pool = { n = 5, items = {} }, unit = 2000, kind = "own",
        capped = true },
      { name = "1 sale here: the other faction's too", listed = { 2900, 2 }, sales = sold(1, { median = 3000 }),
        pool = { n = 5, items = { [901] = { from = "f", own = 1, sib = 6, rest = 0, median = 2800, sales = {} } } },
        unit = 2800, kind = "pooled", from = "f", own = 1, sib = 6 },
      { name = "none here and 25 listed: the region's", listed = { 3000, 25 }, sales = sold(0),
        pool = { n = 5, items = { [901] = { from = "r", own = 0, sib = 2, rest = 4, median = 1500, sales = {} } } },
        unit = 1500, kind = "pooled", from = "r", listed25 = true },
      { name = "a pooled price over a lot here: the lot", listed = { 2500, 1 }, sales = sold(1, { median = 3000 }),
        pool = { n = 5, items = { [901] = { from = "f", own = 1, sib = 6, rest = 0, median = 2800, sales = {} } } },
        unit = 2500, kind = "pooled", capped = true },
      { name = "too few in the whole region: nothing, each sale kept", sales = sold(2, { median = 700 }),
        pool = { n = 5, items = { [901] = { from = "-", own = 2, sib = 1, rest = 0,
          sales = { { where = "o", copper = 500 }, { where = "f", copper = 900 } } } } },
        kind = "none", saleCount = 2 },
      { name = "sold nowhere: nothing", sales = sold(0), pool = { n = 5, items = {} }, kind = "none" },
    }
    for _, case in ipairs(CASES) do
      it(case.name, function()
        load()
        if case.listed then VALUES[901] = scan(case.listed[1], { currentQty = case.listed[2] }) end
        GC.Data.ForeverSales = function(id) return id == 901 and case.sales or nil end
        local pool = case.sales and case.pool or nil
        GC.Data.ForeverPoolMin = function() return pool and pool.n end
        GC.Data.ForeverPool = function(id) return pool and pool.items[id] end
        local unit, perDay, basis = CC.SellOf(901)
        assert.equal(case.unit, unit)
        assert.equal(not case.noPace and case.sales and case.sales.perDay or nil, perDay)
        assert.equal(case.kind, basis.kind)
        assert.equal(case.thin, basis.thin)
        assert.equal(case.capped, basis.capped)
        if case.from then assert.equal(case.from, basis.from) end
        if case.own then assert.same({ case.own, case.sib }, { basis.own, basis.sib }) end
        if case.listed25 then assert.equal(25, basis.listed) end
        if case.saleCount then assert.equal(case.saleCount, #basis.sales) end
      end)
    end

    it("carries the output's basis on the recipe's result, priced or not", function()
      load()
      prices()
      ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
      GC.Data.ForeverSales = function() return sold(1, { median = 3000 }) end
      GC.Data.ForeverPoolMin = function() return 5 end
      local entry = { from = "f", own = 1, sib = 6, rest = 0, median = 2800, sales = {} }
      GC.Data.ForeverPool = function(id) return id == 901 and entry or nil end
      local result = CC.ProfitOf(CC.Snapshot(1))
      assert.equal("pooled", result.basis.kind)
      assert.equal(math.floor(2000 * 0.95) - 160, result.profit) -- held to the 2,000c lot here
      entry = nil
      result = CC.ProfitOf(CC.Snapshot(1))
      assert.equal("none", result.basis.kind)
      assert.is_table(result.missing)
      assert.is_nil(result.thin)
    end)

    -- Owner, 2026-11-24: what a craft makes at the cheapest lot of the freshest scan, any depth, as
    -- Auctionator says it. It never prices the craft.
    it("says what a craft makes at today's cheapest lot, whatever is listed", function()
      load()
      prices()
      VALUES[901] = scan(2600, { min = 29230, currentQty = 3 })
      ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
      local result = CC.ProfitOf(CC.Snapshot(1))
      assert.same({ unit = 29230, profit = math.floor(29230 * 0.95) - 160 }, result.scan)
      assert.is_table(result.missing) -- 3 listed price nothing without sales
      VALUES[901] = scan(2600, { currentQty = 3 })
      assert.is_nil(CC.ProfitOf(CC.Snapshot(1)).scan)
      ROOT.foreverVendor = nil -- a reagent without a price: no cost to measure against
      VALUES[901] = scan(2600, { min = 29230 })
      assert.is_nil(CC.ProfitOf(CC.Snapshot(1)).scan)
    end)
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
    assert.same({ 2000, 37.4 }, { (CC.SellOf(901)), (select(2, CC.SellOf(901))) })
    assert.is_true(P._rows[1].widget.pace:IsShown())
    assert.equal(GC.L["about %s a day"]:format("37"), P._rows[1].widget.pace.text:GetText())
    -- The tape covered the item and nothing sold: a slow seller, said so.
    perDay = 0
    P.Refresh()
    assert.equal(GC.L["Slow seller"], P._rows[1].widget.pace.text:GetText())
  end)

  -- A lot can hang at a price nobody pays. What the item sold for (the tape's median, already the
  -- lowest of the week, the day and six hours) holds the price a craft is counted at; a listing
  -- under it stands, since the craft has to undercut it.
  it("counts a craft at what the item sold for when the cheapest listing asks more", function()
    load()
    VALUES[901] = scan(2000)
    local median = 1500
    GC.Data.ForeverSales = function() return { units = 100, sales = 50, median = median, perDay = 20, hours = 120 } end
    assert.equal(1500, (CC.SellOf(901)))
    median = 2600
    assert.equal(2000, (CC.SellOf(901)))
    -- Nothing sold over the tape: no median to hold it to, the listing stands and the row says slow.
    GC.Data.ForeverSales = function() return { units = 0, sales = 0, perDay = 0, hours = 120 } end
    assert.same({ 2000, 0 }, { (CC.SellOf(901)), (select(2, CC.SellOf(901))) })
  end)

  -- ClickUp 1an60dzww4h: on a market that rose, the tape's median (the lowest of the week, the day
  -- and six hours) is last week's price. What it sells for now, when the site says, holds it instead.
  it("counts a craft at what the item sells for now when the site says, else at the tape's median", function()
    load()
    VALUES[901] = scan(2000)
    local recent = 1800
    GC.Data.ForeverSales = function() return { units = 100, sales = 50, median = 300, recent = recent, perDay = 20, hours = 120 } end
    assert.equal(1800, (CC.SellOf(901)))
    -- Over the cheapest listing: the listing stands.
    recent = 2600
    assert.equal(2000, (CC.SellOf(901)))
    -- No word from the site (a site from before it, or an item it leaves out): the median, as before.
    recent = nil
    assert.equal(300, (CC.SellOf(901)))
  end)

  -- The Companion's payload read as the game reads it (Core/ImportString.lua, Core/Data.lua), not
  -- stubbed: the bag sold once here and 6 times on the other faction's house for 30s; the cheapest
  -- of the 3 listed here asks 20s, the house's AH value 21s.
  it("prices from a real payload's E, capped by the house's AH value, with today's cheapest lot", function()
    load()
    GC.Game = { Passport = function() return { interface = 16001, build = "x", regionId = 90 } end,
      IsForever = function() return true end }
    helper.loadModule("Core/ImportString.lua", GC)
    helper.loadModule("Core/Data.lua", GC)
    GC.Data.Init({ settings = {} })
    ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
    assert.is_table(GC.Data.AdoptForeverPayload("GCF1;s;90;R;Horde;1790000000;"
      .. "I:901=2000=2100=2100=2200=3=1=0,2589=50=50=50=50=40=1=0;H:168;S:901=1=1=3500=3500;E:5,901=f=1=6=0=3000==",
      { region = 90, realm = "R", faction = "Horde" }))
    local unit, _, basis = CC.SellOf(901)
    assert.same({ 2100, "pooled", "f", 1, 6, true }, { unit, basis.kind, basis.from, basis.own, basis.sib, basis.capped })
    local result = CC.ProfitOf(CC.Snapshot(1))
    assert.equal(math.floor(2100 * 0.95) - 160, result.profit)
    assert.same({ unit = 2000, profit = math.floor(2000 * 0.95) - 160 }, result.scan)
  end)

  -- Worth crafting in three groups: a proven price, an estimate from the nearest markets, none.
  describe("recipes without a proven price", function()
    local SALES, POOL
    local NAMES = { "Own Belt", "Pooled Cloak", "Lossy Robe", "Unsold Hat", "Earthen Silk Belt" }

    -- Recipe id makes 900 + id from one of 100 + id. The belt sold 6 times here; the cloak once
    -- here, with the other faction's an estimate; the robe's region estimate is under its cost;
    -- the hat sold nowhere; the silk belt has 3 listed, none sold, its reagent at 1g 76s 52c.
    local function world(learned)
      local recipes, filtered = {}, {}
      for id, name in ipairs(NAMES) do
        recipes[id] = { info = TS.info(id, name, { learned = not (learned and learned[id] == false) }),
          schematic = TS.schematic(id, 900 + id, { TS.slot(1, 1, TS.items(100 + id)) }) }
        filtered[id] = id
      end
      load({ recipes = recipes, filtered = filtered, open = { recipeID = 5, allocations = {} } })
      for id = 101, 104 do VALUES[id] = scan(100) end
      VALUES[105] = scan(17652)
      VALUES[905] = scan(29230, { min = 29230, currentQty = 3 })
      SALES = { [901] = { units = 6, sales = 6, median = 2000, perDay = 6 / 7, hours = 168 },
        [902] = { units = 1, sales = 1, median = 3500, perDay = 1 / 7, hours = 168 } }
      POOL = { [902] = { from = "f", own = 1, sib = 6, rest = 0, median = 3000, sales = {} },
        [903] = { from = "r", own = 0, sib = 2, rest = 3, median = 50, sales = {} } }
      GC.Data.ForeverSales = function(id) return SALES[id] or { units = 0, sales = 0, perDay = 0, hours = 168 } end
      GC.Data.ForeverPoolMin = function() return 5 end
      GC.Data.ForeverPool = function(id) return POOL[id] end
      GC.ForeverScan._faction = "Horde"
    end

    local function groups()
      local out = {}
      for _, row in ipairs((P.Rows())) do out[#out + 1] = { row.name, row.group } end
      return out
    end

    it("lists each in its group, a loss last among the estimates, the listed ones first among none", function()
      world()
      assert.is_true(P.ShowsUnproven())
      assert.same({ { "Own Belt", "main" }, { "Pooled Cloak", "estimate" }, { "Lossy Robe", "estimate" },
        { "Earthen Silk Belt", "none" }, { "Unsold Hat", "none" } }, groups())
      local _, unpriced, unprofitable = P.Rows()
      assert.same({ 0, 0 }, { unpriced, unprofitable })
    end)

    -- No E (an older site, or E dropped for size): a proven price from 20 listed or more, as before,
    -- and a thin book among those with no estimate while the switch is on.
    it("without E prices from the listings as before, a thin book among none", function()
      world()
      GC.Data.ForeverPoolMin = function() return nil end
      VALUES[901] = scan(2000, { currentQty = 25 })
      VALUES[902] = scan(2000, { currentQty = 19, min = 1500 })
      -- The robe and the hat have nothing listed: no price, counted under the list as before.
      assert.same({ { "Own Belt", "main" }, { "Earthen Silk Belt", "none" }, { "Pooled Cloak", "none" } }, groups())
      assert.same({ 2, 0 }, { select(2, P.Rows()) })
      assert.equal("+" .. GC.Util.Money(1800), (function() show() return P._rows[1].widget.profit:GetText() end)())
      assert.same({ "listings", "listings" }, { P._rows[1].result.basis.kind, P._rows[2].result.basis.kind })
      GC.db.craftUnproven = false
      assert.same({ { "Own Belt", "main" } }, groups())
      assert.same({ 4, 0 }, { select(2, P.Rows()) })
    end)

    it("quotes the markets' median for an estimate a cheaper lot here caps", function()
      world()
      VALUES[902] = scan(2500, { currentQty = 1 })
      show()
      local cloak = P._rows[2]
      assert.equal(math.floor(2500 * 0.95) - 100, cloak.result.profit)
      assert.truthy(cloak.widget.math:GetText():find(GC.L["About %s from %d sales: %d here, %d %s"]:format(
        GC.Util.Money(3000), 7, 1, 6, GC.L["Alliance"]), 1, true))
    end)

    it("shows only the first group with the switch off, the rest counted as having no price", function()
      world()
      local f = show()
      local toggle = f.worth.unproven
      assert.equal(GC.L["Without a proven price too"], toggle.text:GetText())
      toggle:GetScript("OnClick")(toggle)
      assert.is_false(GC.db.craftUnproven)
      assert.same({ { "Own Belt", "main" } }, groups())
      assert.same({ 4, 0 }, { select(2, P.Rows()) })
      assert.equal(GC.L["%d have no GoldCap price for a reagent or what they make."]:format(4), f.worth.unpriced:GetText())
      for _, head in ipairs(f.worth.groupHeads) do assert.is_false(head:IsShown()) end
      toggle:GetScript("OnClick")(toggle)
      assert.is_true(P.ShowsUnproven())
    end)

    it("never lists a recipe not learned in either group, whatever the switch", function()
      world({ [2] = false, [4] = false })
      GC.db.craftUnlearned = true
      assert.same({ { "Own Belt", "main" }, { "Lossy Robe", "estimate" }, { "Earthen Silk Belt", "none" } }, groups())
      assert.same({ 0, 0 }, { select(2, P.Rows()) })
    end)

    it("heads each group, and says on its rows what the price rests on and what today's cheapest lot makes", function()
      world()
      local f = show()
      local heads = f.worth.groupHeads
      assert.equal(GC.Util.Upper(GC.L["Estimated from other markets"]), heads[1]:GetText())
      assert.equal(GC.Util.Upper(GC.L["No estimate"]), heads[2]:GetText())
      assert.is_true(heads[2]:IsShown())
      local cloak, robe, silk = P._rows[2].widget, P._rows[3].widget, P._rows[4].widget
      local profit = math.floor(3000 * 0.95) - 100
      assert.equal(GC.L["about +%s"]:format(GC.Util.Money(profit)), cloak.profit:GetText())
      assert.equal(GC.Util.Money(math.floor(50 * 0.95) - 100), robe.profit:GetText())
      local pooled = GC.L["About %s from %d sales: %d here, %d %s"]:format(GC.Util.Money(3000), 7, 1, 6, GC.L["Alliance"])
      assert.truthy(cloak.math:GetText():find(pooled, 1, true))
      assert.truthy(cloak.math:GetText():find(GC.L["%d here at %s"]:format(1, GC.Util.Money(3500)), 1, true))
      assert.equal("+" .. GC.Util.Money(1800), P._rows[1].widget.profit:GetText()) -- a proven price as before
      -- Earthen Silk Belt: floor(29230 x 0.95) - 17652 = 10116 at its cheapest lot.
      local lot = GC.L["At today's cheapest lot %s: %s"]:format(GC.Util.Money(29230), "+" .. GC.Util.Money(10116))
      assert.truthy(silk.math:GetText():find(lot, 1, true))
      assert.truthy(silk.math:GetText():find(GC.L["%d listed here, none sold this week"]:format(3), 1, true))
      assert.equal("", silk.profit:GetText())
      assert.is_false(P._rows[1].widget.math:GetText():find(GC.L["At today's cheapest lot %s: %s"]:sub(1, 8), 1, true) ~= nil)
      -- This recipe (the silk belt) says it too.
      assert.truthy(f.card.missing:GetText():find(lot, 1, true))
      assert.is_table(P.RowTip(P._rows[4]))
    end)

    it("words what the region sold, another region's price and what the item is worth unsold", function()
      world()
      POOL[904] = { from = "-", own = 0, sib = 1, rest = 1,
        sales = { { where = "f", copper = 900 }, { where = "r", copper = 1200 } },
        xregion = { region = "us", sales = 7, median = 150000 } }
      GC.ForeverValue = { VendorUnit = function(id) return id == 904 and 120 or nil end }
      local text = GC.CraftStrip.Lines(CC.ProfitOf(CC.Snapshot(4)))[1].text
      for _, line in ipairs({
        GC.L["Sold %d times: %s"]:format(2, GC.Util.Money(900) .. ", " .. GC.Util.Money(1200)),
        GC.L["Sells for %s in %s"]:format(GC.Util.Money(150000), "US"),
        GC.L["If it does not sell: vendor %s"]:format(GC.Util.Money(120)),
        GC.L["Not seen on your auction house"],
      }) do
        assert.truthy(text:find(line, 1, true), line)
      end
      -- A sale found puts it first among none.
      assert.same({ "Unsold Hat", "none" }, groups()[4])
      -- A priced estimate's lines carry what it rests on.
      local lines = GC.CraftStrip.Lines(CC.ProfitOf(CC.Snapshot(2)))
      assert.truthy(lines[4].text:find(GC.L["About %s from %d sales: %d here, %d %s"]:format(GC.Util.Money(3000), 7, 1, 6,
        GC.L["Alliance"]), 1, true))
    end)
  end)

  it("names the deposit a post of one takes in a row's tooltip, and that a sale returns it", function()
    load()
    prices()
    VALUES[901] = scan(2000)
    ROOT.foreverVendor = { v = 1, items = { [2320] = { u = 10, at = 1 } } }
    GC.ForeverValue = { CommodityDepositUnit = function(id) return id == 901 and 100 or nil end }
    show()
    local lines = P.RowTip(P._rows[1])
    assert.same({ GC.L["Deposit to post one"], GC.L["%s, back when it sells"]:format(GC.Util.Money(100)) }, lines[#lines])
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
