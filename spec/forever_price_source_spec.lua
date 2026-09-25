local helper = require("spec.spec_helper")

describe("the own WoW: Forever scan in the price lookup", function()
  local GC, db
  local FIXTURE = "GCS1;eu;silvermoon;2000;I:190396=123400=52.3;W:190396"

  local function passport(interface)
    return { passport = function() return { interface = interface, region = 90, realm = "Forever" } end }
  end

  local function load(interface)
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Game.lua", GC)
    GC.Game.Passport = function() return { interface = interface, build = "x", regionId = 90 } end
    helper.loadModule("Core/ImportString.lua", GC)
    helper.loadModule("Core/Data.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    db = { settings = {}, foreverScan = { fold = { region = 90, realm = "Forever", at = 5000,
      items = { [2589] = "67,4060,31,;0x936 3x3000" } } } }
    GC.db = db
    GC.ForeverScan.Init(db, passport(interface))
    GC.Data.Init(db)
  end

  after_each(function()
    _G.GoldCap_MarketData = nil
    _G.GoldCap_AppData = nil
    _G.GetCVar = nil
  end)

  it("answers from the scan when nothing else prices the item", function()
    load(16001)
    local v = GC.Data.GetItemValue(2589)
    assert.equal("scan", v.source)
    assert.equal("own_scan", v.kind)
    assert.equal(67, v.mv)
    assert.equal(4060, v.currentQty)
    assert.equal(5000, v.ts)
    assert.is_nil(GC.Data.GetItemValue(1))
  end)

  it("lets any other source outrank the scan", function()
    _G.GetCVar = function(k) if k == "portal" then return "US" end end
    _G.GoldCap_MarketData = { us = { ts = 1, items = { [2589] = { m = 50 } } } }
    load(16001)
    assert.equal("bundled", GC.Data.GetItemValue(2589).source)
  end)

  it("never answers from a scan on retail, even with a fold in the save", function()
    load(120100)
    assert.is_nil(GC.Data.GetItemValue(2589))
  end)

  it("adopts no companion string in WoW: Forever, and still does on retail", function()
    load(16001)
    _G.GoldCap_AppData = { importString = FIXTURE, writtenAt = 2000 }
    GC.Data.AdoptAppData()
    assert.is_nil(db.imported)
    assert.is_nil(db.appDataError)
    load(120100)
    _G.GoldCap_AppData = { importString = FIXTURE, writtenAt = 2000 }
    GC.Data.AdoptAppData()
    assert.equal("app", db.imported.origin)
  end)

  it("arms nothing and measures no deal against one player's scan", function()
    load(16001)
    local v = GC.Data.GetItemValue(2589)
    local cfg = { minimumProfitCopper = 1, minimumRoi = 0, watchDiscount = 0.05 }
    assert.is_nil(GC.Trigger.For(v, cfg))
    assert.is_true(#GC.SniperDecision.PreScreen(GC.SniperDecision.MarketFromValue(v), cfg) > 0)
    assert.is_nil(GC.DealMath.Measure(10, 1, v))
    assert.is_nil(GC.DealMath.Evaluate({ itemID = 2589, unitPrice = 10, qty = 1 }, v, cfg))
  end)
end)
