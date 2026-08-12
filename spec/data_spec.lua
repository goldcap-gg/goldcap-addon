local helper = require("spec.spec_helper")

describe("Data", function()
  local GC, db

  before_each(function()
    _G.GetCVar = function(k) if k == "portal" then return "EU" end end
    _G.GoldCap_MarketData = {
      eu = { ts = 1000, items = { [42] = { m = 5000, s = 1.5 }, [43] = { m = 700, l = 9 } } },
      us = { ts = 1000, items = { [42] = { m = 9999 } } },
    }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", GC)
    helper.loadModule("Core/Data.lua", GC)
    db = { settings = {} }
    GC.db = db
    GC.Data.Init(db)
  end)

  after_each(function()
    _G.GetCVar = nil
    _G.GoldCap_MarketData = nil
  end)

  it("detects region from the portal cvar", function()
    assert.equal("eu", GC.Data.GetStatus().region)
  end)

  it("returns bundled values for the detected region", function()
    local v = GC.Data.GetItemValue(42)
    assert.equal(5000, v.mv)
    assert.equal(1.5, v.sold)
    assert.equal("bundled", v.source)
    assert.equal(1000, v.ts)
  end)

  it("returns listings for item entries", function()
    assert.equal(9, GC.Data.GetItemValue(43).listings)
  end)

  it("returns nil for unknown items", function()
    assert.is_nil(GC.Data.GetItemValue(777))
  end)

  it("prefers imported entries over bundled", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                          items = { [42] = { m = 4000 } }, watchlist = {} })
    local v = GC.Data.GetItemValue(42)
    assert.equal(4000, v.mv)
    assert.equal("import", v.source)
    assert.equal(2000, v.ts)
    -- bundled still answers for items absent from the import:
    assert.equal("bundled", GC.Data.GetItemValue(43).source)
  end)

  it("passes an imported entry's trend through as `trend`", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                          items = { [42] = { m = 4000, t = -12 } }, watchlist = {} })
    assert.equal(-12, GC.Data.GetItemValue(42).trend)
  end)

  it("merges imported verification facts and classifies a verified import as commodity", function()
    GC.Data.SetImported({
      region = "eu", realm = "silvermoon", ts = 2000,
      items = { [42] = { m = 4000, s = 3, t = -2 } },
      verification = {
        [42] = {
          sourceAt = 1999, stressUnit = 3500, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 20, listings = 3,
          observations = 12, madBps = 100, flags = 129,
        },
      },
      watchlist = {},
    })

    local v = GC.Data.GetItemValue(42)
    assert.equal("region_commodity", v.kind)
    assert.equal(1999, v.sourceAt)
    assert.equal(3500, v.stressUnit)
    assert.equal(7000, v.sellThroughBps)
    assert.equal(70, v.liquidityConfidence)
    assert.equal(20, v.currentQty)
    assert.equal(3, v.listings)
    assert.equal(12, v.observations)
    assert.equal(100, v.madBps)
    assert.is_true(v.estimated)
  end)

  it("keeps imported legacy entries as realm items and bundled values non-buyable", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                          items = { [42] = { m = 4000 } }, watchlist = {} })
    assert.equal("realm_item", GC.Data.GetItemValue(42).kind)

    local bundled = GC.Data.GetItemValue(43)
    assert.equal("realm_item", bundled.kind)
    assert.is_nil(bundled.sourceAt)
    assert.is_nil(bundled.stressUnit)
  end)

  it("persists verification facts when companion app data is adopted", function()
    _G.GoldCap_AppData = {
      importString = "GCS1;eu;silvermoon;2000;I:42=4000=3;V:42=1999=3500=7000=70=20=3=12=100=1",
    }
    GC.Data.AdoptAppData()

    assert.equal(1999, db.imported.verification[42].sourceAt)
    assert.is_true(GC.Data.GetItemValue(42).estimated)
  end)

  it("leaves trend nil for an imported entry with no trend field", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                          items = { [42] = { m = 4000 } }, watchlist = {} })
    assert.is_nil(GC.Data.GetItemValue(42).trend)
  end)

  it("never surfaces trend for a bundled entry (bundled data has none)", function()
    -- No import in effect here, so 42 answers from the bundled table (see
    -- the before_each fixture) -- which has no `t` field to pass through.
    assert.is_nil(GC.Data.GetItemValue(42).trend)
  end)

  it("persists imports into the db table and reports status", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                          items = { [1] = { m = 1 } }, watchlist = {} })
    assert.equal("silvermoon", db.imported.realm)
    local st = GC.Data.GetStatus()
    assert.equal(2000, st.importedTs)
    assert.equal("silvermoon", st.importedRealm)
    assert.equal(1, st.importedCount)
    assert.equal(2, st.bundledCount)
  end)

  it("falls back to us when the portal cvar is unavailable", function()
    _G.GetCVar = nil
    local GC2 = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Data.lua", GC2)
    GC2.Data.Init({ settings = {} })
    assert.equal("us", GC2.Data.GetStatus().region)
  end)

  describe("watchlist", function()
    it("persists the watchlist from an import", function()
      GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                            items = { [1] = { m = 10 } }, watchlist = { 5, 1 } })
      assert.same({ 5, 1 }, db.imported.watchlist)
      assert.same({ 5, 1 }, GC.Data.GetWatchlist())
    end)

    it("falls back to top imported items by value when W is empty", function()
      GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                            items = { [1] = { m = 10 }, [2] = { m = 300 }, [3] = { m = 20 } },
                            watchlist = {} })
      assert.same({ 2, 3, 1 }, GC.Data.GetWatchlist())
    end)

    it("caps the fallback at fallbackN", function()
      GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                            items = { [1] = { m = 10 }, [2] = { m = 300 }, [3] = { m = 20 } },
                            watchlist = {} })
      assert.same({ 2 }, GC.Data.GetWatchlist(1))
    end)

    it("returns an empty list with no import", function()
      assert.same({}, GC.Data.GetWatchlist())
    end)

    it("returns a copy, not the persisted watchlist", function()
      GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                            items = { [1] = { m = 10 } }, watchlist = { 5, 1 } })
      local w = GC.Data.GetWatchlist()
      w[1] = 999
      table.remove(w)
      assert.same({ 5, 1 }, db.imported.watchlist)
    end)

    it("breaks ties by item id", function()
      GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                            items = { [9] = { m = 100 }, [2] = { m = 100 }, [5] = { m = 300 } },
                            watchlist = {} })
      assert.same({ 5, 2, 9 }, GC.Data.GetWatchlist())
    end)

    it("clamps a negative cap to an empty list", function()
      GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                            items = { [1] = { m = 10 }, [2] = { m = 300 } },
                            watchlist = {} })
      assert.same({}, GC.Data.GetWatchlist(-1))
    end)
  end)
end)
