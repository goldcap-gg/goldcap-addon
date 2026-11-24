local helper = require("spec.spec_helper")

-- A commodity's typical day of sales (the D section of GCM1 and GCS1): the median of the units it
-- sold on each of the last 7 complete days. DEALS sizes a buy from it instead of the last 24 hours,
-- which one busy day multiplies tenfold.
describe("a commodity's typical day of sales", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", GC)
  end)

  describe("the D section", function()
    local CASES = {
      { name = "present", tail = ";D:42=900,44=0", want = { [42] = 900, [44] = 0 } },
      { name = "absent", tail = "", want = nil },
      { name = "empty", tail = ";D:", want = nil },
      { name = "with malformed tokens, which drop themselves alone",
        tail = ";D:42=900,x=1,43=-5,0=7,44=1.5,45=,=9,46=12=3,47=30", want = { [42] = 900, [47] = 30 } },
      { name = "with nothing readable", tail = ";D:x,=,1=", want = {} },
    }
    for _, case in ipairs(CASES) do
      it("in GCM1 " .. case.name, function()
        local r = assert(GC.ImportString.ParseRegion("GCM1;eu;3000;I:42=4100=6.0,44=900,47=10" .. case.tail))
        assert.same(case.want, r.typical)
        assert.equal(3, r.counts.items)
      end)
      it("in GCS1 " .. case.name, function()
        local r = assert(GC.ImportString.Parse("GCS1;eu;silvermoon;3000;I:42=4100=6.0,44=900,47=10;N:9" .. case.tail))
        assert.same(case.want, r.typical)
        assert.same({ 9 }, r.namesWanted)
      end)
    end

    it("sits beside P and K in GCM1 without changing what they read", function()
      local r = assert(GC.ImportString.ParseRegion("GCM1;eu;3000;I:42=4100=6.0,7=2;K:7=5000=12;P:42=61,7=30"
        .. ";D:42=900,7=bad"))
      assert.same({ [42] = 900 }, r.typical)
      assert.same({ [7] = { floor5th = 5000, realms = 12 } }, r.cheap)
      assert.same({ [42] = 61, [7] = 30 }, r.sellChance)
      assert.same({ m = 4100, s = 6 }, r.items[42])
    end)

    it("leaves an old payload yielding exactly what it did", function()
      local r = GC.ImportString.ParseRegion("GCM1;eu;3000;I:42=4100=6.0=-3,44=900;Q:42=4000;R:42=4300;P:42=61")
      assert.same({
        region = "eu", ts = 3000,
        items = { [42] = { m = 4100, s = 6, t = -3 }, [44] = { m = 900 } },
        verification = {}, quarter = { [42] = 4000 }, reach = { [42] = 4300 }, refs = {}, refListings = {},
        counts = { items = 2, facts = 0, refs = 0 }, sellChance = { [42] = 61 },
      }, r)
      local s = GC.ImportString.Parse("GCS1;eu;silvermoon;3000;I:42=4100=6.0;W:42;N:9")
      assert.same({
        region = "eu", realm = "silvermoon", ts = 3000,
        items = { [42] = { m = 4100, s = 6 } }, verification = {}, quarter = {}, reach = {}, targets = {},
        watchlist = { 42 }, namesWanted = { 9 },
      }, s)
    end)
  end)

  describe("the item's value", function()
    local db

    before_each(function()
      _G.GetCVar = function(k) if k == "portal" then return "EU" end end
      _G.GoldCap_MarketData = { eu = { ts = 1000, items = {} } }
      helper.loadModule("Core/Data.lua", GC)
      helper.loadModule("Core/SniperDecision.lua", GC)
      db = { settings = {} }
      GC.db = db
      GC.Data.Init(db)
    end)

    after_each(function()
      _G.GetCVar = nil
      _G.GoldCap_MarketData = nil
    end)

    local function import(ts, tail)
      GC.Data.SetImported(assert(GC.ImportString.Parse("GCS1;eu;silvermoon;" .. ts .. ";I:42=4000=3,43=500=8,44=70=2"
        .. ";V:42=1=5000=7000=70=1=3=12=0=0,43=1=5000=7000=70=1=3=12=0=0,44=1=5000=7000=70=1=3=12=0=0" .. tail)))
    end
    local function payload(tail)
      assert(GC.Data.AdoptRegionPayload("GCM1;eu;3000;I:42=4100=6.0,43=510=9.0;V:42=2990=3800=8000=85=40=4=12=90=0" .. tail))
    end
    local function typical(itemID) return GC.Data.GetItemValue(itemID).typical end

    it("is the payload's figure, and none without D", function()
      payload(";D:42=900")
      assert.equal(900, typical(42))
      assert.is_nil(typical(43))
      assert.equal(900, GC.SniperDecision.MarketFromValue(GC.Data.GetItemValue(42)).typicalPerDay)
      payload("")
      assert.is_nil(typical(42))
    end)

    it("is the import's when only the import carries D, and survives the save", function()
      import(2000, ";D:42=800,44=40")
      assert.equal(800, db.imported.typical[42])
      assert.equal(800, typical(42))
      assert.equal(40, typical(44))
      import(2000, "")
      assert.is_nil(db.imported.typical)
      assert.is_nil(typical(42))
    end)

    -- The newer of the two that name the item, as the facts are; the payload on the same ts.
    it("is the newer source's when both carry D, item by item", function()
      import(2000, ";D:42=800,43=60,44=40")
      payload(";D:42=900")
      assert.equal(900, typical(42))
      assert.equal(60, typical(43))
      assert.equal(40, typical(44))
      import(4000, ";D:42=800")
      assert.equal(800, typical(42))
      import(3000, ";D:42=800")
      assert.equal(900, typical(42))
    end)
  end)

  -- EU Starlight Ink: 75 to 1,909 a day for two weeks, 43,280 on one day, about 900 on a typical one.
  describe("the demand cap", function()
    local config = { maxDailyDemandShare = 0.05, maxQuantity = 5000 }
    local function cap(today, typicalDay)
      helper.loadModule("Core/SniperDecision.lua", GC)
      return GC.SniperDecision.DemandCap({ soldPerDay = today, typicalPerDay = typicalDay, currentQty = 3000, madBps = 0 },
        config, 0)
    end

    it("sizes from the typical day on a spike day, not from the spike", function()
      assert.equal(1821, cap(43280, nil))
      assert.equal(9, cap(43280, 900))
    end)

    it("sizes from the typical day on a quiet day, where today alone buys next to nothing", function()
      assert.equal(1, cap(75, nil))
      assert.equal(9, cap(75, 900))
      assert.equal(0, cap(5, nil))
      assert.equal(9, cap(5, 900))
    end)

    it("reads a typical day of 0 as one, and today's figure where there is none", function()
      assert.equal(0, cap(43280, 0))
      helper.loadModule("Core/SniperDecision.lua", GC)
      assert.equal(900, GC.SniperDecision.CapPerDay({ soldPerDay = 43280, typicalPerDay = 900 }))
      assert.equal(43280, GC.SniperDecision.CapPerDay({ soldPerDay = 43280 }))
      assert.equal(43280, GC.SniperDecision.CapPerDay({ soldPerDay = 43280, typicalPerDay = 0 / 0 }))
      assert.is_nil(GC.SniperDecision.CapPerDay({}))
    end)

    it("is the figure the Check prints as sold a day and counts its days by", function()
      helper.loadModule("Core/SniperDecision.lua", GC)
      helper.loadModule("Core/CheckVerdict.lua", GC)
      local market = { marketValue = 30400, stressUnit = 27700, soldPerDay = 43280, typicalPerDay = 900,
        sellThroughBps = 8800, liquidityConfidence = 90, listings = 17, currentQty = 3000 }
      local v = GC.CheckVerdict.Build({ status = "AVOID", buyable = false, reasons = { "sell_through_too_low" },
        quantity = 1800, entryTotal = 1800 * 31100, exitUnit = 27700 }, market)
      local shown
      for _, fact in ipairs(v.facts) do
        if fact.id == "soldPerDay" then shown = fact.count end
      end
      assert.equal(900, shown)
      assert.same({ kind = "days", days = 2 }, v.hero)
    end)
  end)
end)
