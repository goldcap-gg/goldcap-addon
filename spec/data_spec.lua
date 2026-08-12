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

  it("passes an imported entry's trend through as `trend`", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                          items = { [42] = { m = 4000, t = -12 } }, watchlist = {} })
    assert.equal(-12, GC.Data.GetItemValue(42).trend)
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

  describe("post stats / personal sale rate (F2)", function()
    describe("RecordPostEvent", function()
      it("creates an entry on first post and counts it", function()
        GC.Data.RecordPostEvent(42, "Ironclaw Ore")
        assert.equal(1, db.postStats[42].posts)
        assert.equal(0, db.postStats[42].sales)
        assert.equal("Ironclaw Ore", db.postStats[42].name)
      end)

      it("increments posts on repeat calls for the same item", function()
        GC.Data.RecordPostEvent(42, "Ironclaw Ore")
        GC.Data.RecordPostEvent(42, "Ironclaw Ore")
        assert.equal(2, db.postStats[42].posts)
      end)

      it("refreshes the cached name when a real name is passed", function()
        GC.Data.RecordPostEvent(42, "Old Name")
        GC.Data.RecordPostEvent(42, "New Name")
        assert.equal("New Name", db.postStats[42].name)
      end)

      it("keeps the existing name when itemName is nil", function()
        GC.Data.RecordPostEvent(42, "Ironclaw Ore")
        GC.Data.RecordPostEvent(42, nil)
        assert.equal("Ironclaw Ore", db.postStats[42].name)
      end)

      it("is a no-op before GC.Data.Init has ever run", function()
        local GC2 = helper.loadModule("Core/Data.lua")
        assert.has_no.errors(function() GC2.Data.RecordPostEvent(1, "x") end)
      end)

      it("evicts a least-posted entry once the cap is exceeded, keeping heavier-posted entries", function()
        for i = 1, 500 do
          GC.Data.RecordPostEvent(i, "item" .. i)
        end
        -- Give every item except #500 a second post, so #500 sits as the unambiguous single
        -- minimum (posts=1) among the first 500 entries -- which of the two posts=1 entries
        -- (#500 or the freshly-added #501) actually gets evicted is not something this test
        -- needs to pin down; only that the cap holds and every HEAVIER-posted entry survives.
        for i = 1, 499 do
          GC.Data.RecordPostEvent(i, "item" .. i)
        end
        GC.Data.RecordPostEvent(501, "item501") -- 501st distinct item -> triggers eviction

        local count = 0
        for _ in pairs(db.postStats) do count = count + 1 end
        assert.equal(500, count)
        for i = 1, 499 do
          assert.is_not_nil(db.postStats[i])
          assert.equal(2, db.postStats[i].posts)
        end
      end)
    end)

    describe("RecordSaleEvent", function()
      it("increments sales for the postStats entry whose name matches", function()
        GC.Data.RecordPostEvent(42, "Ironclaw Ore")
        GC.Data.RecordSaleEvent("Ironclaw Ore")
        assert.equal(1, db.postStats[42].sales)
      end)

      it("counts multiple sales of the same item", function()
        GC.Data.RecordPostEvent(42, "Ironclaw Ore")
        GC.Data.RecordSaleEvent("Ironclaw Ore")
        GC.Data.RecordSaleEvent("Ironclaw Ore")
        assert.equal(2, db.postStats[42].sales)
      end)

      it("is a silent no-op when no postStats entry matches the name", function()
        assert.has_no.errors(function() GC.Data.RecordSaleEvent("Never Posted") end)
      end)

      it("is a silent no-op before any post has ever been recorded (no postStats table yet)", function()
        assert.has_no.errors(function() GC.Data.RecordSaleEvent("Ironclaw Ore") end)
      end)

      it("is nil-safe for a nil itemName", function()
        GC.Data.RecordPostEvent(42, "Ironclaw Ore")
        assert.has_no.errors(function() GC.Data.RecordSaleEvent(nil) end)
        assert.equal(0, db.postStats[42].sales)
      end)
    end)

    describe("GetSaleRate", function()
      it("returns nil when there is no postStats entry for the item", function()
        assert.is_nil(GC.Data.GetSaleRate(42))
      end)

      it("returns nil below the 3-post confidence threshold", function()
        GC.Data.RecordPostEvent(42, "Ironclaw Ore")
        GC.Data.RecordPostEvent(42, "Ironclaw Ore")
        assert.is_nil(GC.Data.GetSaleRate(42))
      end)

      it("answers once posts reaches exactly 3", function()
        for _ = 1, 3 do GC.Data.RecordPostEvent(42, "Ironclaw Ore") end
        GC.Data.RecordSaleEvent("Ironclaw Ore")
        GC.Data.RecordSaleEvent("Ironclaw Ore")
        local r = GC.Data.GetSaleRate(42)
        assert.equal(3, r.posts)
        assert.equal(2, r.sales)
        assert.equal(2 / 3, r.rate)
      end)

      it("clamps a rate above 100% (a manual post's sale counted where RecordPostEvent never saw the posting)", function()
        for _ = 1, 3 do GC.Data.RecordPostEvent(42, "Ironclaw Ore") end
        for _ = 1, 5 do GC.Data.RecordSaleEvent("Ironclaw Ore") end
        local r = GC.Data.GetSaleRate(42)
        assert.equal(1, r.rate)
      end)
    end)
  end)
end)
