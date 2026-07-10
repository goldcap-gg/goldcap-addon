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
