local helper = require("spec.spec_helper")

describe("Data.AdoptAppData", function()
  local GC, db

  -- Real GCS1 fixture (same shape as importstring_spec.lua's) so this exercises the actual
  -- ImportString.Parse path, not a stub.
  local FIXTURE_TS2000 = "GCS1;eu;silvermoon;2000;I:190396=123400=52.3;W:190396"
  local REGION_2000 = "GCM1;eu;2000;I:190396=123000=50.0"
    .. ";V:190396=1990=110000=8000=85=400=6=12=90=0;M:201234=990000=4"

  before_each(function()
    _G.GetCVar = function(k) if k == "portal" then return "EU" end end
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
    _G.GoldCap_AppData = nil
  end)

  it("adopts app data when there is no existing import", function()
    _G.GoldCap_AppData = { importString = FIXTURE_TS2000, writtenAt = 2000 }
    GC.Data.AdoptAppData()
    assert.equal("app", db.imported.origin)
    assert.equal("silvermoon", db.imported.realm)
    assert.equal("eu", db.imported.region)
    assert.equal(2000, db.imported.ts)
    assert.equal(123400, db.imported.items[190396].m)
    assert.same({ 190396 }, db.imported.watchlist)
  end)

  it("mirrors the manual-import storage shape (region/realm/ts/items/watchlist + origin)", function()
    _G.GoldCap_AppData = { importString = FIXTURE_TS2000, writtenAt = 2000 }
    GC.Data.AdoptAppData()
    local keys = {}
    for k in pairs(db.imported) do keys[#keys + 1] = k end
    table.sort(keys)
    assert.same({ "items", "namesWanted", "origin", "realm", "region", "ts", "watchlist" }, keys)
  end)

  -- The companion writes whatever the site hands it, R section or not. The shape test above
  -- pins the no-R case (no `reach` key at all); this one pins that a string carrying one does
  -- reach the save through the same path.
  it("carries an R section through the companion path", function()
    _G.GoldCap_AppData = { writtenAt = 2000,
      importString = "GCS1;eu;silvermoon;2000;I:190396=123400=52.3;R:190396=99900;W:190396" }
    GC.Data.AdoptAppData()
    assert.equal(99900, db.imported.reach[190396])
    assert.equal(99900, GC.Data.GetItemValue(190396).reach)
  end)

  -- Same contract for T: a companion build that predates the section writes none, and the
  -- shape test above already pins that this path leaves no `targets` key behind for it.
  it("carries a T section through the companion path", function()
    _G.GoldCap_AppData = { writtenAt = 2000,
      importString = "GCS1;eu;silvermoon;2000;I:190396=123400=52.3;T:190396=200000=623;W:190396" }
    GC.Data.AdoptAppData()
    assert.equal(200000, db.imported.targets[190396].ref)
    assert.equal(623, GC.Data.GetItemValue(190396).refIlvl)
    assert.same({ 190396 }, GC.Data.TargetIds())
  end)

  it("reports no targets at all for a companion string with no T section", function()
    _G.GoldCap_AppData = { importString = FIXTURE_TS2000, writtenAt = 2000 }
    GC.Data.AdoptAppData()
    assert.same({}, GC.Data.TargetIds())
  end)

  it("adopts app data when strictly newer than the existing (manual) import", function()
    GC.Data.SetImported({ region = "eu", realm = "oldrealm", ts = 1000,
                          items = { [1] = { m = 1 } }, watchlist = {} })
    db.imported.origin = "manual"
    _G.GoldCap_AppData = { importString = FIXTURE_TS2000, writtenAt = 2000 }
    GC.Data.AdoptAppData()
    assert.equal("app", db.imported.origin)
    assert.equal("silvermoon", db.imported.realm)
    assert.equal(2000, db.imported.ts)
  end)

  it("keeps the manual import when app data is older", function()
    GC.Data.SetImported({ region = "eu", realm = "newer", ts = 5000,
                          items = { [1] = { m = 1 } }, watchlist = {} })
    db.imported.origin = "manual"
    _G.GoldCap_AppData = { importString = FIXTURE_TS2000, writtenAt = 2000 } -- ts 2000 < 5000
    GC.Data.AdoptAppData()
    assert.equal("manual", db.imported.origin)
    assert.equal("newer", db.imported.realm)
    assert.equal(5000, db.imported.ts)
  end)

  it("keeps the existing import when timestamps are equal (no churn)", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 2000,
                          items = { [1] = { m = 1 } }, watchlist = {} })
    db.imported.origin = "manual"
    _G.GoldCap_AppData = { importString = FIXTURE_TS2000, writtenAt = 2000 } -- same ts (2000)
    GC.Data.AdoptAppData()
    assert.equal("manual", db.imported.origin)
    assert.is_nil(db.imported.items[190396]) -- app fixture's item never got adopted in
    assert.equal(1, db.imported.items[1].m) -- original manual data untouched
  end)

  it("ignores a malformed importString and leaves existing data untouched", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 1000,
                          items = { [1] = { m = 1 } }, watchlist = {} })
    db.imported.origin = "manual"
    _G.GoldCap_AppData = { importString = "not-a-GCS1-string", writtenAt = 9999 }
    GC.Data.AdoptAppData()
    assert.equal("manual", db.imported.origin)
    assert.equal(1000, db.imported.ts)
  end)

  it("is a no-op when GoldCap_AppData is absent", function()
    assert.has_no.errors(function() GC.Data.AdoptAppData() end)
    assert.is_nil(db.imported)
  end)

  it("is a no-op when GoldCap_AppData is present but not a table", function()
    _G.GoldCap_AppData = "oops"
    assert.has_no.errors(function() GC.Data.AdoptAppData() end)
    assert.is_nil(db.imported)
  end)

  it("records why a companion payload was rejected", function()
    _G.GoldCap_AppData = { importString = "GCS1;zz;silvermoon;1;I:1=10", writtenAt = 9999 }
    GC.Data.AdoptAppData()
    local err = GC.Data.AppDataError()
    assert.equal("bad_region", err.reason)
    assert.equal(9999, err.writtenAt)
  end)

  it("complains once per writtenAt, not once per call", function()
    local printed = {}
    GC.Print = function(msg) printed[#printed + 1] = msg end
    _G.GoldCap_AppData = { importString = "GCS1;zz;silvermoon;1;I:1=10", writtenAt = 9999 }
    GC.Data.AdoptAppData()
    GC.Data.AdoptAppData()
    assert.equal(1, #printed)
    _G.GoldCap_AppData.writtenAt = 10000
    GC.Data.AdoptAppData()
    assert.equal(2, #printed)
  end)

  it("clears the recorded error once a good payload arrives", function()
    _G.GoldCap_AppData = { importString = "GCS1;zz;silvermoon;1;I:1=10", writtenAt = 9999 }
    GC.Data.AdoptAppData()
    _G.GoldCap_AppData = { importString = FIXTURE_TS2000, writtenAt = 10000 }
    GC.Data.AdoptAppData()
    assert.is_nil(GC.Data.AppDataError())
    assert.equal("app", db.imported.origin)
  end)

  it("describes each error code in a sentence a player can act on", function()
    assert.is_truthy(GC.Data.DescribeImportError("bad_region"):find("update", 1, true))
    assert.is_string(GC.Data.DescribeImportError("no_items"))
    assert.is_string(GC.Data.DescribeImportError("something-new"))
    -- The parser's two newer refusals need sentences too, or they print as bare codes.
    assert.is_truthy(GC.Data.DescribeImportError("no_realm"):find("realm", 1, true))
    assert.is_truthy(GC.Data.DescribeImportError("two_strings"):find("two", 1, true))
  end)

  -- No GoldCap_AppData at all is the standalone case and not a fault. One that IS there and
  -- carries no string is the companion having run and written something unusable -- which
  -- used to leave in silence, with /goldcap status reporting nothing wrong.
  it("records a companion payload that carries no string at all", function()
    _G.GoldCap_AppData = { writtenAt = 2000 }
    assert.has_no.errors(function() GC.Data.AdoptAppData() end)
    assert.is_nil(db.imported)
    assert.equal("empty", GC.Data.AppDataError().reason)
    assert.equal(2000, GC.Data.AppDataError().writtenAt)
  end)

  it("says nothing at all when the companion was never installed", function()
    GC.Print = function() error("should not print") end
    assert.has_no.errors(function() GC.Data.AdoptAppData() end)
    assert.is_nil(GC.Data.AppDataError())
  end)

  -- The old gate was the PERSISTED error record, so a broken companion write was announced
  -- once and never again -- not next login, not next week, while every session went on using
  -- whatever stale prices were left.
  it("says a failure again in a new session, not once ever", function()
    local printed = {}
    GC.Print = function(msg) printed[#printed + 1] = msg end
    _G.GoldCap_AppData = { importString = "GCS1;zz;silvermoon;1;I:1=10", writtenAt = 9999 }
    GC.Data.AdoptAppData()
    assert.equal(1, #printed)

    -- A new session: the same SavedVariables, the same unchanged companion file, a fresh load.
    local next_ = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", next_)
    helper.loadModule("Core/Data.lua", next_)
    next_.Print = function(msg) printed[#printed + 1] = msg end
    next_.db = db
    next_.Data.Init(db)
    next_.Data.AdoptAppData()
    assert.equal(2, #printed)
  end)

  -- A manual paste that works is the answer to "the Companion wrote prices I could not
  -- read": the recorded error describes a payload that is no longer what is loaded, and it
  -- used to survive for good -- /goldcap status kept reporting a sync failure at a player
  -- whose prices were fine.
  it("clears a recorded companion error when a manual import lands", function()
    _G.GoldCap_AppData = { importString = "GCS1;zz;silvermoon;1;I:1=10", writtenAt = 9999 }
    GC.Data.AdoptAppData()
    assert.is_not_nil(GC.Data.AppDataError())
    GC.Data.SetImported(GC.ImportString.Parse(FIXTURE_TS2000))
    assert.is_nil(GC.Data.AppDataError())
  end)

  it("keeps the region payload in memory and out of the saved variables", function()
    _G.GoldCap_AppData = { writtenAt = 2000, importString = FIXTURE_TS2000, regionString = REGION_2000 }
    GC.Data.AdoptAppData()

    local payload = GC.Data.RegionPayload()
    assert.is_truthy(payload)
    assert.equal(123000, GC.Data.GetItemValue(190396).mv)

    local held = {}
    local function mark(t)
      held[t] = true
      for _, v in pairs(t) do
        if type(v) == "table" and not held[v] then mark(v) end
      end
    end
    mark(payload)
    local seen = {}
    local function walk(t, path)
      if seen[t] then return end
      seen[t] = true
      for k, v in pairs(t) do
        assert.is_nil(held[v], "GoldCapDB reaches the region payload at " .. path .. "." .. tostring(k))
        if type(v) == "table" then walk(v, path .. "." .. tostring(k)) end
      end
    end
    walk(db, "db")

    local keys = {}
    for k in pairs(db.imported) do keys[#keys + 1] = k end
    table.sort(keys)
    assert.same({ "items", "namesWanted", "origin", "realm", "region", "ts", "watchlist" }, keys)
  end)

  it("lets go of the raw payload string once it is parsed", function()
    _G.GoldCap_AppData = { writtenAt = 2000, importString = FIXTURE_TS2000, regionString = REGION_2000 }
    GC.Data.AdoptAppData()
    assert.is_nil(_G.GoldCap_AppData.regionString)
    assert.equal(FIXTURE_TS2000, _G.GoldCap_AppData.importString)
  end)

  -- It is never saved, so every load has to read it again -- even when the import string is not
  -- newer than the one already stored and is (rightly) not adopted.
  it("adopts the payload on a load whose import string is not newer", function()
    GC.Data.SetImported({ region = "eu", realm = "silvermoon", ts = 3000,
      items = { [1] = { m = 1 } }, watchlist = {} })
    _G.GoldCap_AppData = { writtenAt = 2000, importString = FIXTURE_TS2000, regionString = REGION_2000 }
    GC.Data.AdoptAppData()
    assert.equal(3000, db.imported.ts)
    assert.is_truthy(GC.Data.RegionPayload())
  end)

  it("ignores another region's payload", function()
    _G.GoldCap_AppData = { writtenAt = 2000, importString = FIXTURE_TS2000,
      regionString = "GCM1;us;2000;I:190396=5=1.0" }
    GC.Data.AdoptAppData()
    assert.is_nil(GC.Data.RegionPayload())
    assert.equal("import", GC.Data.GetItemValue(190396).source)
  end)

  it("behaves exactly as before when the payload does not parse", function()
    _G.GoldCap_AppData = { writtenAt = 2000, importString = FIXTURE_TS2000, regionString = "garbage" }
    GC.Data.AdoptAppData()
    assert.is_nil(GC.Data.RegionPayload())
    assert.is_nil(db.appDataError)
    assert.equal("app", db.imported.origin)
    assert.equal(123400, GC.Data.GetItemValue(190396).mv)
  end)

  -- A payload dated 0 or ahead of the clock would make every fact-less item it prices look fresh
  -- for as long as it stays loaded (such an item's age is the payload's). An hour of slack is
  -- clock skew between the player's machine and the site, not a date to believe.
  it("refuses a payload dated 0 or more than an hour ahead", function()
    local realTime = _G.time
    _G.time = function() return 100000 end
    local ok, err = pcall(function()
      _G.GoldCap_AppData = { writtenAt = 2000, importString = FIXTURE_TS2000,
        regionString = "GCM1;eu;0;I:190396=5=1.0" }
      GC.Data.AdoptAppData()
      assert.is_nil(GC.Data.RegionPayload())
      assert.is_nil(_G.GoldCap_AppData.regionString)
      assert.equal(123400, GC.Data.GetItemValue(190396).mv)

      local payload, reason = GC.Data.AdoptRegionPayload("GCM1;eu;103601;I:190396=5=1.0")
      assert.is_nil(payload)
      assert.equal("bad_ts", reason)
      assert.is_nil(GC.Data.RegionPayload())

      assert.is_truthy(GC.Data.AdoptRegionPayload("GCM1;eu;103600;I:190396=5=1.0"))
      assert.equal(5, GC.Data.GetItemValue(190396).mv)
    end)
    _G.time = realTime
    assert(ok, err)
  end)

  -- Counts every collectgarbage call `fn` makes, by option ("collect", "count", ...).
  local function countingCollects(fn)
    local real, calls = _G.collectgarbage, {}
    _G.collectgarbage = function(opt, ...)
      calls[opt or "collect"] = (calls[opt or "collect"] or 0) + 1
      return real(opt, ...)
    end
    local ok, err = pcall(fn)
    _G.collectgarbage = real
    assert(ok, err)
    return calls
  end

  -- A full collection walks every addon's heap, not just this one's: forced at load it is a hitch
  -- on every login and /reload, paid for a figure nobody may ever ask for.
  it("forces no garbage collection at load", function()
    _G.GoldCap_AppData = { writtenAt = 2000, importString = FIXTURE_TS2000, regionString = REGION_2000 }
    local calls = countingCollects(function() GC.Data.AdoptAppData() end)
    assert.is_truthy(GC.Data.RegionPayload())
    assert.same({}, calls)
  end)

  -- /goldcap status prints it as what the payload costs this session. Measured when asked, on a
  -- clean heap, by building the payload's tables again: what the parsed tables keep -- not the
  -- garbage the parse left behind, which is half as much again, and not a figure a collection
  -- already under way could shrink to 0.
  it("measures what the payload keeps in memory when asked, and only once", function()
    assert.is_nil(GC.Data.RegionPayloadMemoryKB())

    local tokens, refs = {}, {}
    for i = 1, 4000 do tokens[i] = (100000 + i) .. "=" .. (1000 + i) .. "=12.5" end
    for i = 1, 8000 do refs[i] = (300000 + i) .. "=20000=3" end
    local str = "GCM1;eu;2000;I:" .. table.concat(tokens, ",") .. ";M:" .. table.concat(refs, ",")
    assert.is_truthy(GC.Data.AdoptRegionPayload(str))

    local reported
    local calls = countingCollects(function()
      reported = GC.Data.RegionPayloadMemoryKB()
      assert.equal(reported, GC.Data.RegionPayloadMemoryKB())
    end)
    assert.equal(1, calls.collect)

    collectgarbage("collect")
    local withPayload = collectgarbage("count")
    GC.Data.AdoptRegionPayload(nil)
    collectgarbage("collect")
    local kept = withPayload - collectgarbage("count")

    assert.is_true(kept > 0)
    assert.is_true(math.abs(reported - kept) <= kept * 0.1 + 16,
      ("reported %.0f KB for a payload that keeps %.0f KB"):format(reported, kept))
    assert.is_nil(GC.Data.RegionPayloadMemoryKB())
  end)
end)
