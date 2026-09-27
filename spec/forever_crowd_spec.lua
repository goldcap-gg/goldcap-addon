local helper = require("spec.spec_helper")

-- WoW: Forever crowd prices: the Companion's GCF1 payload (the site's plan 2a, Task 9), read
-- into the tooltip and the Deals board (plan 3d, Part A).
describe("GCF1, the WoW: Forever crowd payload", function()
  local GC
  local TS = 1790000000
  local BODY = "GCF1;us-beta-classic-beta-pve-2-horde;90;Classic Beta PvE 2;Horde;" .. TS
    .. ";I:2589=68=70=69=79=7000=2=0=g,2592=255=269===2029=1=20"

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", GC)
  end)

  it("reads the header and every token", function()
    local p = GC.ImportString.ParseForever(BODY)
    assert.equal("us-beta-classic-beta-pve-2-horde", p.slug)
    assert.equal(90, p.regionId)
    assert.equal("Classic Beta PvE 2", p.realm)
    assert.equal("Horde", p.faction)
    assert.equal(TS, p.ts)
    assert.equal(2, p.count)
    assert.same({ min = 68, ah = 70, mv = 69, p50 = 79, qty = 7000, w = 2, age = 0, gear = true }, p.items[2589])
    assert.same({ min = 255, ah = 269, qty = 2029, w = 1, age = 20 }, p.items[2592])
  end)

  it("unescapes the realm and reads a dash as no faction", function()
    local p = GC.ImportString.ParseForever("GCF1;s;90;Odd%3BRealm%25;-;" .. TS .. ";I:1=2=2===3=1=0")
    assert.equal("Odd;Realm%", p.realm)
    assert.is_nil(p.faction)
  end)

  it("drops a malformed token alone, skips a section it does not know", function()
    local p = GC.ImportString.ParseForever("GCF1;s;90;R;Horde;" .. TS .. ";I:1=2=2===3=1=0,oops,3=x;Z:whatever")
    assert.equal(1, p.count)
    assert.is_not_nil(p.items[1])
  end)

  it("refuses what is not a Forever payload", function()
    assert.same({ nil, "empty" }, { GC.ImportString.ParseForever(nil) })
    assert.same({ nil, "bad_header" }, { GC.ImportString.ParseForever("GCM1;eu;1;I:1=2") })
    assert.same({ nil, "bad_header" }, { GC.ImportString.ParseForever("GCS1;eu;x;1;I:1=2") })
    assert.same({ nil, "no_items" }, { GC.ImportString.ParseForever("GCF1;s;90;R;Horde;1;I:") })
    assert.same({ nil, "too_long" }, { GC.ImportString.ParseForever(("x"):rep(GC.ImportString.FOREVER_MAX_LEN + 1)) })
  end)
end)

describe("adopting the crowd payload", function()
  local GC, db
  local NOW = 1790000600
  local TS = 1790000000
  local function body(realm, faction, region)
    return ("GCF1;s;%d;%s;%s;%d;I:2589=68=70=69=79=7000=2=0"):format(region or 90, realm or "Classic Beta PvE 2", faction or "Horde", TS)
  end

  local function load(interface, realm, faction)
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Game.lua", GC)
    GC.Game.Passport = function() return { interface = interface, build = "x", regionId = 90 } end
    helper.loadModule("Core/ImportString.lua", GC)
    helper.loadModule("Core/Data.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    db = { settings = {} }
    GC.db = db
    GC.ForeverScan.Init(db, { passport = function()
      return { interface = interface, region = 90, realm = realm or "Classic Beta PvE 2", faction = faction or "Horde" }
    end })
    GC.Data.Init(db)
  end

  before_each(function() _G.time = function() return NOW end end)
  after_each(function() _G.GoldCap_AppData = nil; _G.time = os.time end)

  it("adopts the Forever payload in WoW: Forever and drops the raw string once read", function()
    load(16001)
    _G.GoldCap_AppData = { foreverString = body(), foreverUpload = true, writtenAt = NOW }
    GC.Data.AdoptAppData()
    assert.equal(1, GC.Data.ForeverPayload().count)
    assert.is_nil(_G.GoldCap_AppData.foreverString)
    assert.is_true(GC.Data.CompanionShares())
  end)

  it("never adopts another market's prices as this character's", function()
    for _, case in ipairs({
      { "Classic Beta PvP 1", "Horde" },   -- another realm
      { "Classic Beta PvE 2", "Alliance" }, -- the other faction
    }) do
      load(16001, case[1], case[2])
      _G.GoldCap_AppData = { foreverString = body() }
      GC.Data.AdoptAppData()
      assert.is_nil(GC.Data.ForeverPayload(), case[1] .. " " .. case[2])
    end
    load(16001)
    _G.GoldCap_AppData = { foreverString = body(nil, nil, 1) } -- another region id
    GC.Data.AdoptAppData()
    assert.is_nil(GC.Data.ForeverPayload())
  end)

  it("a payload naming no faction serves both", function()
    load(16001, nil, "Alliance")
    _G.GoldCap_AppData = { foreverString = body(nil, "-") }
    GC.Data.AdoptAppData()
    assert.is_not_nil(GC.Data.ForeverPayload())
  end)

  it("refuses a payload dated more than an hour ahead of this clock", function()
    load(16001)
    local p, why = GC.Data.AdoptForeverPayload(body():gsub(tostring(TS), tostring(NOW + 7200)),
      { region = 90, realm = "Classic Beta PvE 2", faction = "Horde" })
    assert.is_nil(p)
    assert.equal("future", why)
  end)

  it("in WoW: Forever a retail string is still refused, as before", function()
    load(16001)
    _G.GoldCap_AppData = { importString = "GCS1;eu;silvermoon;2000;I:190396=123400=52.3;W:190396", foreverString = body() }
    GC.Data.AdoptAppData()
    assert.is_nil(db.imported)
    assert.is_nil(db.appDataError)
    assert.is_not_nil(GC.Data.ForeverPayload())
  end)

  it("on retail nothing changes: the import is adopted, a stray foreverString is ignored", function()
    load(120100)
    _G.GoldCap_AppData = { importString = "GCS1;eu;silvermoon;2000;I:190396=123400=52.3;W:190396", foreverString = body() }
    GC.Data.AdoptAppData()
    assert.equal("app", db.imported.origin)
    assert.is_nil(GC.Data.ForeverPayload())
    assert.equal(body(), _G.GoldCap_AppData.foreverString, "retail does not even read it")
  end)

  it("an older companion writes nothing into the Forever install: no payload, no sharing, no error", function()
    load(16001)
    _G.GoldCap_AppData = nil
    GC.Data.AdoptAppData()
    assert.is_nil(GC.Data.ForeverPayload())
    assert.is_false(GC.Data.CompanionShares())
  end)
end)

describe("the fresher look prices the tooltip", function()
  local GC, db
  local NOW = 1790003600
  local TS = 1790000000 -- the crowd's newest scan; item 2589 scanned then (age 0)

  local function load(foldAt)
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Game.lua", GC)
    GC.Game.Passport = function() return { interface = 16001, build = "x", regionId = 90 } end
    helper.loadModule("Core/ImportString.lua", GC)
    helper.loadModule("Core/Data.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("UI/Tooltip.lua", GC)
    db = { settings = {}, foreverScan = { fold = { region = 90, realm = "R", at = foldAt,
      items = { [2589] = "67,4060,31,;0x936 3x3000" } } } }
    GC.db = db
    GC.ForeverScan.Init(db, { passport = function() return { interface = 16001, region = 90, realm = "R", faction = "Horde" } end })
    GC.Data.Init(db)
    GC.Data.AdoptForeverPayload(("GCF1;s;90;R;Horde;%d;I:2589=68=75=74=79=7000=3=0,2592=255=269===2029=1=20"):format(TS),
      { region = 90, realm = "R", faction = "Horde" })
  end

  before_each(function() _G.time = function() return NOW end end)
  after_each(function() _G.time = os.time end)

  it("the crowd answers when it looked more recently than the player", function()
    load(TS - 600)
    local v = GC.Data.GetItemValue(2589)
    assert.equal("crowd", v.kind)
    assert.equal("scan", v.source)
    assert.equal(75, v.mv)
    assert.equal(3, v.scanners)
    assert.equal(TS, v.ts)
    assert.equal(79, v.p50)
  end)

  it("the player's own newer scan wins for their own tooltip", function()
    load(TS + 60)
    local v = GC.Data.GetItemValue(2589)
    assert.equal("own_scan", v.kind)
  end)

  it("an item only the crowd has is still priced, dated by its own age", function()
    load(TS + 60)
    local v = GC.Data.GetItemValue(2592)
    assert.equal("crowd", v.kind)
    assert.equal(TS - 20 * 60, v.ts)
    assert.is_nil(v.marketValue)
  end)

  it("a crowd price is not a market either: no deal is measured against it", function()
    load(TS - 600)
    assert.is_nil(GC.DealMath.Measure(10, 1, GC.Data.GetItemValue(2589)))
  end)

  it("the tooltip says how many players scanned it and when", function()
    load(TS - 600)
    local lines = GC.Tooltip.BuildLines(GC.Data.GetItemValue(2589), NOW, {})
    assert.equal("AH value", lines[1].label)
    assert.equal(75, lines[1].copper)
    local source
    for _, l in ipairs(lines) do if l.left == "Source" then source = l.right end end
    assert.equal("3 scanners, 1h ago", source)
    local one = GC.Tooltip.BuildLines({ mv = 5, ts = NOW - 300, source = "scan", kind = "crowd", scanners = 1 }, NOW, {})
    assert.equal("1 scanner, 5m ago", one[#one].right)
  end)

  it("the player's own scan still says so, exactly as before", function()
    load(TS + 60)
    local lines = GC.Tooltip.BuildLines(GC.Data.GetItemValue(2589), NOW, {})
    assert.equal("your scan, 59m ago", lines[#lines].right)
  end)
end)
