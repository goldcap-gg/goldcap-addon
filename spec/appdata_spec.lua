local helper = require("spec.spec_helper")

describe("Data.AdoptAppData", function()
  local GC, db

  -- Real GCS1 fixture (same shape as importstring_spec.lua's) so this exercises the actual
  -- ImportString.Parse path, not a stub.
  local FIXTURE_TS2000 = "GCS1;eu;silvermoon;2000;I:190396=123400=52.3;W:190396"

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
    assert.same({ "items", "origin", "realm", "region", "ts", "watchlist" }, keys)
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

  it("is a no-op when importString is missing or not a string", function()
    _G.GoldCap_AppData = { writtenAt = 2000 }
    assert.has_no.errors(function() GC.Data.AdoptAppData() end)
    assert.is_nil(db.imported)
  end)
end)
