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

  it("keeps namesWanted on the imported snapshot", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                          items = { [42] = { m = 4000 } }, watchlist = {},
                          namesWanted = { 201421 } })
    assert.same({ 201421 }, db.imported.namesWanted)
  end)

  it("keeps the cheap-quarter line through SetImported", function()
    local parsed = GC.ImportString.Parse("GCS1;eu;x;2000;I:42=6000=3.0;V:42=1=5000=1=1=1=1=1=1=0;Q:42=6500")
    GC.Data.SetImported(parsed)
    assert.equal(6500, GC.Data.GetItemValue(42).p25)
    assert.equal(6500, db.imported.quarter[42])
  end)

  it("leaves no quarter field on a save when the string carried no Q section", function()
    GC.Data.SetImported(GC.ImportString.Parse("GCS1;eu;x;2000;I:42=6000"))
    assert.is_nil(db.imported.quarter)
    assert.is_nil(GC.Data.GetItemValue(42).p25)
  end)

  -- SetImported copies a NAMED field list, so a new section reaches the save only if it is
  -- named there. R was parsed and dropped on the floor until it was.
  it("keeps the reach line through SetImported", function()
    local parsed = GC.ImportString.Parse("GCS1;eu;x;2000;I:42=6000=3.0;Q:42=6500;R:42=6200")
    GC.Data.SetImported(parsed)
    assert.equal(6200, GC.Data.GetItemValue(42).reach)
    assert.equal(6200, db.imported.reach[42])
  end)

  it("leaves no reach field on a save when the string carried no R section", function()
    GC.Data.SetImported(GC.ImportString.Parse("GCS1;eu;x;2000;I:42=6000;Q:42=6500"))
    assert.is_nil(db.imported.reach)
    assert.is_nil(GC.Data.GetItemValue(42).reach)
    assert.equal(6500, GC.Data.GetItemValue(42).p25)
  end)

  -- Sniper phase 2 (T section): the region reference price for a realm item, and the item
  -- level of the variant that reference was measured on.
  it("keeps the region reference line through SetImported", function()
    local parsed = GC.ImportString.Parse("GCS1;eu;x;2000;I:42=6000;T:42=9000=610")
    GC.Data.SetImported(parsed)
    local v = GC.Data.GetItemValue(42)
    assert.equal(9000, v.ref)
    assert.equal(610, v.refIlvl)
    assert.equal(6000, v.mv)
    assert.equal(9000, db.imported.targets[42].ref)
  end)

  it("leaves no targets field on a save when the string carried no T section", function()
    GC.Data.SetImported(GC.ImportString.Parse("GCS1;eu;x;2000;I:42=6000"))
    assert.is_nil(db.imported.targets)
    assert.is_nil(GC.Data.GetItemValue(42).ref)
  end)

  -- A T item need not appear in I at all: the region knows a reference price for it while
  -- this realm has no median of its own. Without a value table there is no trigger, and the
  -- item would never be polled -- which is the whole point of the section.
  it("answers for a target the I section never mentioned", function()
    GC.Data.SetImported(GC.ImportString.Parse("GCS1;eu;x;2000;I:42=6000;T:99=1234=0"))
    local v = GC.Data.GetItemValue(99)
    assert.equal(1234, v.ref)
    assert.equal(0, v.refIlvl)
    assert.is_nil(v.mv)
    assert.equal("realm_item", v.kind)
    assert.equal("import", v.source)
  end)

  it("returns the target ids in ascending order, and an empty list without a T section", function()
    GC.Data.SetImported(GC.ImportString.Parse("GCS1;eu;x;2000;I:42=6000;T:99=1234=0,7=50=0,42=9000=610"))
    assert.same({ 7, 42, 99 }, GC.Data.TargetIds())
    GC.Data.SetImported(GC.ImportString.Parse("GCS1;eu;x;2001;I:42=6000"))
    assert.same({}, GC.Data.TargetIds())
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

  describe("OriginState", function()
    it("reports none when nothing has been imported", function()
      assert.equal("none", GC.Data.OriginState())
    end)

    it("reports manual after a manual paste (nil origin marker)", function()
      GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                            items = { [1] = { m = 1 } }, watchlist = {} })
      assert.equal("manual", GC.Data.OriginState())
    end)

    it("reports app after the companion adopts its data", function()
      _G.GoldCap_AppData = {
        importString = "GCS1;eu;silvermoon;2000;I:42=4000=3",
      }
      GC.Data.AdoptAppData()
      assert.equal("app", GC.Data.OriginState())
    end)
  end)

  it("falls back to us when the portal cvar is unavailable", function()
    _G.GetCVar = nil
    local GC2 = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Data.lua", GC2)
    GC2.Data.Init({ settings = {} })
    assert.equal("us", GC2.Data.GetStatus().region)
  end)

  -- Serving US prices to a player the addon cannot place was silent: the fallback is fine
  -- (a price table has to come from somewhere) but nothing on screen said the region was a
  -- guess. A PTR portal is the real-world case -- the CVar reads, and names nothing known.
  describe("undetectable region", function()
    local function loadWith(portal, store)
      _G.GetCVar = function(k) if k == "portal" then return portal end end
      local GC2 = helper.loadModule("Core/Util.lua")
      helper.loadModule("Core/ImportString.lua", GC2)
      helper.loadModule("Core/Data.lua", GC2)
      local printed = {}
      GC2.Print = function(msg) printed[#printed + 1] = msg end
      GC2.Data.Init(store or { settings = {} })
      return GC2, printed
    end

    it("says once that the region is a guess and the prices are bundled US", function()
      local GC2, printed = loadWith("public-test")
      assert.equal("us", GC2.Data.GetStatus().region)
      assert.equal(1, #printed)
      assert.is_truthy(printed[1]:find("US", 1, true))
      GC2.Data.WarnRegionUnknown() -- a second ask in the same session stays quiet
      assert.equal(1, #printed)
    end)

    it("stays quiet once an import has named a region outright", function()
      local _, printed = loadWith("public-test",
        { settings = {}, imported = { region = "eu", realm = "silvermoon", ts = 5, items = {} } })
      assert.equal(0, #printed)
    end)

    it("stays quiet when the portal reads fine", function()
      local _, printed = loadWith("EU")
      assert.equal(0, #printed)
    end)
  end)

  -- Every other entry point here tolerates Init never having run; these two did not, and
  -- AdoptAppData reached straight through SetImported into db.imported.origin.
  it("stores nothing, and errors on nothing, before Init has run", function()
    local GC2 = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", GC2)
    helper.loadModule("Core/Data.lua", GC2)
    assert.has_no.errors(function()
      GC2.Data.SetImported({ region = "eu", realm = "x", ts = 1, items = {}, watchlist = {} })
    end)
    _G.GoldCap_AppData = { importString = "GCS1;eu;silvermoon;2000;I:190396=123400", writtenAt = 2000 }
    assert.has_no.errors(function() GC2.Data.AdoptAppData() end)
    _G.GoldCap_AppData = nil
  end)

  it("detects kr and tw from the portal cvar", function()
    for portal, expected in pairs({ KR = "kr", TW = "tw", US = "us" }) do
      _G.GetCVar = function(k) if k == "portal" then return portal end end
      local GC2 = helper.loadModule("Core/Util.lua")
      helper.loadModule("Core/ImportString.lua", GC2)
      helper.loadModule("Core/Data.lua", GC2)
      GC2.Data.Init({ settings = {} })
      assert.equal(expected, GC2.Data.GetStatus().region)
    end
  end)

  it("prefers the imported string's region over the detected one", function()
    _G.GetCVar = function(k) if k == "portal" then return "KR" end end
    local GC2 = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", GC2)
    helper.loadModule("Core/Data.lua", GC2)
    GC2.Data.Init({ settings = {}, imported = { region = "tw", realm = "skywall", ts = 5, items = {} } })
    assert.equal("tw", GC2.Data.GetStatus().region)
  end)

  it("re-reads the region when an import arrives mid-session", function()
    _G.GetCVar = function(k) if k == "portal" then return "US" end end
    _G.GoldCap_MarketData = { us = { ts = 1, items = { [7] = { m = 5 } } },
                              kr = { ts = 2, items = { [7] = { m = 50 } } } }
    local GC2 = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", GC2)
    helper.loadModule("Core/Data.lua", GC2)
    GC2.Data.Init({ settings = {} })
    assert.equal("us", GC2.Data.GetStatus().region)
    GC2.Data.SetImported({ region = "kr", realm = "azshara", ts = 9, items = {}, watchlist = {} })
    assert.equal("kr", GC2.Data.GetStatus().region)
    assert.equal(50, GC2.Data.GetItemValue(7).mv) -- bundled table followed the region
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

    -- A cap of zero used to sort every item in the import and then remove them one at a
    -- time, which on a full import is thousands of comparisons to produce {}.
    it("answers a zero cap without sorting the import", function()
      GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                            items = { [1] = { m = 10 }, [2] = { m = 300 } },
                            watchlist = {} })
      assert.same({}, GC.Data.GetWatchlist(0))
      -- The player's own list still wins at any cap: that branch returns before this one.
      GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2001,
                            items = { [1] = { m = 10 } }, watchlist = { 5, 1 } })
      assert.same({ 5, 1 }, GC.Data.GetWatchlist(0))
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

  it("exposes the cheap-quarter line from the import, and nothing from bundled", function()
    db.imported = {
      ts = 2000,
      items = { [42] = { m = 6000, s = 3 } },
      verification = { [42] = { sourceAt = 1, stressUnit = 5000, sellThroughBps = 1,
        liquidityConfidence = 1, currentQty = 1, listings = 1, observations = 1, madBps = 0, flags = 0 } },
      quarter = { [42] = 6500 },
    }
    assert.equal(6500, GC.Data.GetItemValue(42).p25)
    assert.is_nil(GC.Data.GetItemValue(43).p25) -- bundled only
  end)

  it("returns no p25 when the import predates the Q section", function()
    db.imported = { ts = 2000, items = { [42] = { m = 6000 } } }
    assert.is_nil(GC.Data.GetItemValue(42).p25)
  end)

  it("exposes the reach line from the import, and nothing from bundled", function()
    db.imported = {
      ts = 2000,
      items = { [42] = { m = 6000, s = 3 } },
      verification = { [42] = { sourceAt = 1, stressUnit = 5000, sellThroughBps = 1,
        liquidityConfidence = 1, currentQty = 1, listings = 1, observations = 1, madBps = 0, flags = 0 } },
      reach = { [42] = 6200 },
    }
    assert.equal(6200, GC.Data.GetItemValue(42).reach)
    assert.is_nil(GC.Data.GetItemValue(43).reach) -- bundled only
  end)

  it("exposes reach on a realm-item entry too, with no verification record", function()
    db.imported = { ts = 2000, items = { [42] = { m = 6000 } }, reach = { [42] = 6200 } }
    assert.equal(6200, GC.Data.GetItemValue(42).reach)
  end)

  it("returns no reach when the import predates the R section", function()
    db.imported = { ts = 2000, items = { [42] = { m = 6000 } }, quarter = { [42] = 6500 } }
    assert.is_nil(GC.Data.GetItemValue(42).reach)
    assert.equal(6500, GC.Data.GetItemValue(42).p25)
  end)
end)
