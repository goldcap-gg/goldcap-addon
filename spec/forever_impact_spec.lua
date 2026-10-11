local helper = require("spec.spec_helper")

-- WoW: Forever, "what your scan changed": the Companion (1.16.0+) writes the site's count for the
-- last upload into GoldCap_AppData.foreverImpact, and the addon says it once per upload at the
-- loading screen after. Which scan an entry belongs to is told by GoldCapDB.foreverScan.foldAts.
local NOW = 1790500000

local function read(path)
  local f = assert(io.open(path))
  local text = f:read("*a")
  f:close()
  return text
end

-- An entry as the Companion writes it. NONE leaves a key out.
local NONE = {}
local function entry(at, over)
  local e = { at = at, updated = 412, onlyYours = 38, realm = "Classic Beta PvE 2", faction = "Alliance" }
  for k, v in pairs(over or {}) do
    if v == NONE then e[k] = nil else e[k] = v end
  end
  return e
end

describe("the scan impact line", function()
  local GC, db, printed

  local function load(interface)
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Game.lua", GC)
    GC.Game.Passport = function() return { interface = interface, build = "x", regionId = 90 } end
    helper.loadModule("Core/ImportString.lua", GC)
    helper.loadModule("Core/Data.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    printed = {}
    GC.Print = function(msg) printed[#printed + 1] = msg end
    db = { settings = {} }
    GC.db = db
    GC.ForeverScan.Init(db, { passport = function()
      return { interface = interface, region = 90, realm = "Classic Beta PvE 2", faction = "Alliance" }
    end })
  end

  -- The client's own BreakUpLargeNumbers, as it groups digits in an English client.
  local function groupDigits(n)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
  end

  before_each(function()
    _G.time = function() return NOW end
    _G.BreakUpLargeNumbers = groupDigits
    load(16001)
    db.foreverScan.foldAts = { 100, 200 }
  end)
  after_each(function()
    _G.time = os.time
    _G.BreakUpLargeNumbers = nil
    _G.FACTION_ALLIANCE, _G.FACTION_HORDE = nil, nil
    _G.GoldCap_AppData = nil
    _G.GetCVar = nil
  end)

  describe("the three lines", function()
    it("says the first scan on a market opened it", function()
      GC.ForeverScan.AdoptImpact({ entry(200, { updated = 2210, onlyYours = 2210, first = true, faction = "Horde" }) })
      assert.is_true(GC.ForeverScan.SayImpact())
      assert.same({ "You opened Classic Beta PvE 2 · Horde: its first 2,210 prices are yours." }, printed)
    end)

    it("says how many prices it updated and how many nobody else had", function()
      GC.ForeverScan.AdoptImpact({ entry(200) })
      GC.ForeverScan.SayImpact()
      assert.same({ "Your scan updated 412 prices on Classic Beta PvE 2 · Alliance. 38 of them nobody else had in the last 24 hours." },
        printed)
    end)

    it("says only what it updated when nobody else's prices were missing", function()
      GC.ForeverScan.AdoptImpact({ entry(200, { onlyYours = 0 }) })
      GC.ForeverScan.SayImpact()
      assert.same({ "Your scan updated 412 prices on Classic Beta PvE 2 · Alliance." }, printed)
    end)

    it("names the market by its realm alone when the Companion sent no faction", function()
      GC.ForeverScan.AdoptImpact({ entry(200, { faction = NONE }) })
      GC.ForeverScan.SayImpact()
      assert.same({ "Your scan updated 412 prices on Classic Beta PvE 2. 38 of them nobody else had in the last 24 hours." },
        printed)
    end)

    it("formats numbers without the client's grouping helper too", function()
      _G.BreakUpLargeNumbers = nil
      GC.ForeverScan.AdoptImpact({ entry(200, { updated = 2210, onlyYours = 0 }) })
      GC.ForeverScan.SayImpact()
      assert.same({ "Your scan updated 2210 prices on Classic Beta PvE 2 · Alliance." }, printed)
    end)

    it("uses the client's own word for the faction, and a | in a name is doubled for chat", function()
      _G.FACTION_ALLIANCE, _G.FACTION_HORDE = "Allianz", "Horde"
      GC.ForeverScan.AdoptImpact({ entry(200, { realm = "Odd|Realm" }) })
      GC.ForeverScan.SayImpact()
      assert.equal("Your scan updated 412 prices on Odd||Realm · Allianz. 38 of them nobody else had in the last 24 hours.",
        printed[1])
    end)

    it("names a faction it does not know as it came", function()
      _G.FACTION_ALLIANCE = "Allianz"
      GC.ForeverScan.AdoptImpact({ entry(200, { faction = "Neutral", onlyYours = 0 }) })
      GC.ForeverScan.SayImpact()
      assert.equal("Your scan updated 412 prices on Classic Beta PvE 2 · Neutral.", printed[1])
    end)
  end)

  describe("when it stays quiet", function()
    it("prints nothing for a scan that updated nothing, and still counts it as said", function()
      GC.ForeverScan.AdoptImpact({ entry(200, { updated = 0, onlyYours = 0 }) })
      assert.is_false(GC.ForeverScan.SayImpact())
      assert.same({}, printed)
      assert.equal(200, db.foreverScan.impactSaidAt)
    end)

    it("prints nothing when the Companion wrote no key (an older one)", function()
      _G.GoldCap_AppData = { foreverString = "x", foreverUpload = true, writtenAt = NOW }
      assert.has_no.errors(GC.Data.AdoptAppData)
      assert.is_false(GC.ForeverScan.SayImpact())
      assert.same({}, printed)
      assert.is_nil(db.foreverScan.impactSaidAt)
    end)

    it("prints nothing for an entry that is not a scan this account made", function()
      GC.ForeverScan.AdoptImpact({ entry(300) })
      assert.is_false(GC.ForeverScan.SayImpact())
      assert.same({}, printed)
      assert.is_nil(db.foreverScan.impactSaidAt)
    end)

    it("prints once per upload: the next loading screen says nothing", function()
      GC.ForeverScan.AdoptImpact({ entry(200) })
      assert.is_true(GC.ForeverScan.SayImpact())
      assert.is_false(GC.ForeverScan.SayImpact())
      assert.equal(1, #printed)
      assert.equal(200, db.foreverScan.impactSaidAt)
      -- a /reload adopts the same file again: still nothing
      GC.ForeverScan.AdoptImpact({ entry(200) })
      assert.is_false(GC.ForeverScan.SayImpact())
      assert.equal(1, #printed)
    end)

    it("never prints an older result after a newer one was said", function()
      GC.ForeverScan.AdoptImpact({ entry(200) })
      GC.ForeverScan.SayImpact()
      GC.ForeverScan.AdoptImpact({ entry(100, { updated = 5, onlyYours = 1 }) })
      assert.is_false(GC.ForeverScan.SayImpact())
      assert.equal(1, #printed)
    end)

    it("says a newer result after an older one", function()
      db.foreverScan.foldAts = { 100, 200 }
      GC.ForeverScan.AdoptImpact({ entry(100, { updated = 5, onlyYours = 1 }) })
      GC.ForeverScan.SayImpact()
      GC.ForeverScan.AdoptImpact({ entry(200) })
      assert.is_true(GC.ForeverScan.SayImpact())
      assert.equal(2, #printed)
      assert.equal(200, db.foreverScan.impactSaidAt)
    end)

    it("prints only the newest of two valid entries", function()
      GC.ForeverScan.AdoptImpact({ entry(100, { updated = 5, onlyYours = 1 }), entry(200) })
      GC.ForeverScan.SayImpact()
      assert.equal(1, #printed)
      assert.truthy(printed[1]:find("412", 1, true))
      assert.is_false(GC.ForeverScan.SayImpact())
    end)

    it("skips another account's newer entry and says this account's", function()
      GC.ForeverScan.AdoptImpact({ entry(999, { updated = 7, onlyYours = 7 }), entry(200) })
      GC.ForeverScan.SayImpact()
      assert.equal(1, #printed)
      assert.truthy(printed[1]:find("412", 1, true))
      assert.equal(200, db.foreverScan.impactSaidAt)
    end)
  end)

  describe("reading the file", function()
    it("drops a malformed entry alone", function()
      GC.ForeverScan.AdoptImpact({
        "oops",
        entry(0),
        entry("200"),
        entry(200.5),
        entry(200, { updated = -1 }),
        entry(200, { updated = 4.5 }),
        entry(200, { updated = "412" }),
        entry(200, { onlyYours = 413 }),
        entry(200, { onlyYours = -1 }),
        entry(200, { first = "yes" }),
        entry(200, { realm = "" }),
        entry(200, { realm = 5 }),
        entry(200, { realm = ("x"):rep(65) }),
        entry(200, { faction = 5 }),
        entry(200, { updated = 0 / 0 }),
        entry(200, { updated = math.huge, onlyYours = 1 }),
        entry(100, { first = true, onlyYours = 412 }), -- valid
        entry(200, { realm = ("x"):rep(64) }),         -- valid
      })
      local kept = GC.ForeverScan._impacts
      assert.equal(2, #kept)
      assert.equal(100, kept[1].at)
      assert.is_true(kept[1].first)
      assert.equal(200, kept[2].at)
      assert.is_false(kept[2].first)
    end)

    it("counts a realm name in characters, not bytes", function()
      local realm = ("Ж"):rep(64) -- 128 bytes, 64 characters
      GC.ForeverScan.AdoptImpact({ entry(200, { realm = realm }) })
      assert.equal(1, #GC.ForeverScan._impacts)
      GC.ForeverScan.AdoptImpact({ entry(200, { realm = realm .. "Ж" }) })
      assert.equal(0, #GC.ForeverScan._impacts)
    end)

    it("leaves what it holds alone for a value that is not a table", function()
      GC.ForeverScan.AdoptImpact({ entry(200) })
      for _, junk in ipairs({ "x", 5, true }) do GC.ForeverScan.AdoptImpact(junk) end
      GC.ForeverScan.AdoptImpact(nil)
      assert.equal(1, #GC.ForeverScan._impacts)
    end)

    it("adopts the key with the rest of the Companion's file and drops it from the global", function()
      _G.GoldCap_AppData = { foreverUpload = true, writtenAt = NOW, foreverImpact = { entry(200) } }
      GC.Data.AdoptAppData()
      assert.is_nil(_G.GoldCap_AppData.foreverImpact)
      assert.is_true(GC.Data.CompanionShares())
      GC.ForeverScan.SayImpact()
      assert.equal(1, #printed)
    end)

    it("reads the key even when the file carries no Forever string", function()
      _G.GoldCap_AppData = { foreverImpact = { entry(200) } }
      GC.Data.AdoptAppData()
      assert.equal(1, #GC.ForeverScan._impacts)
    end)
  end)

  describe("retail", function()
    it("prints no line, keeps no store and adopts the import string as before", function()
      _G.GetCVar = function(k) if k == "portal" then return "EU" end end
      load(120100)
      _G.GoldCap_AppData = { writtenAt = 2000, importString = "GCS1;eu;silvermoon;2000;I:190396=123400=52.3;W:190396",
        foreverImpact = { entry(200) } }
      GC.Data.Init(db)
      GC.Data.AdoptAppData()
      assert.is_false(GC.ForeverScan.SayImpact())
      assert.equal(1, #printed)
      assert.truthy(printed[1]:find("auto-synced data for silvermoon loaded", 1, true))
      assert.is_nil(db.foreverScan)
      assert.is_nil(GC.ForeverScan._impacts)
      assert.equal("app", db.imported.origin)
      assert.is_not_nil(_G.GoldCap_AppData.foreverImpact, "retail does not even read the key")
    end)
  end)
end)

describe("the fold stamps an account remembers", function()
  local GC, timers, store, rows, now

  local function driver()
    return {
      now = function() return now end,
      after = function(s, fn) timers[#timers + 1] = { s = s, fn = fn } end,
      replicate = function() return true end,
      numRows = function() return #rows end,
      rowInfo = function(i)
        local r = rows[i + 1]
        if not r then return nil end
        return r[1], r[2], r[3], r[4]
      end,
      isGear = function() return false end,
      startBrowse = function() return "running" end, -- the browse pass never ends: the watchdog commits
      store = function() return store end,
      passport = function()
        return { interface = 16001, build = "1.60.1.70009", region = 90, realm = "Forever", faction = "Horde" }
      end,
      notify = function() end,
    }
  end

  local function runAll()
    local guard = 0
    while #timers > 0 do
      guard = guard + 1
      assert(guard < 10000, "runaway timers")
      table.remove(timers, 1).fn()
    end
  end

  local function scan(count)
    local s = GC.ForeverScan.New(driver())
    rows = {}
    for i = 1, count do rows[i] = { 1000 + (i % 50), 1, 100 + (i % 7), true } end
    s:OnAuctionHouseShow()
    runAll()
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Game.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverGear.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    timers, store, rows, now = {}, {}, {}, 100000
  end)

  it("adds the stamp of a scan that replaces the saved fold", function()
    scan(500)
    assert.same({ now }, store.foldAts)
    store.requestedAt = nil
    now = now + 3 * 3600 -- past the merge window: a replace
    scan(500)
    assert.same({ now - 3 * 3600, now }, store.foldAts)
  end)

  it("adds nothing when a partial read merges into the saved fold and keeps its stamp", function()
    scan(500)
    local first = store.fold.at
    store.requestedAt = nil
    now = now + 500
    -- the browse pass never ends, so this read is partial, and inside the merge window it tops the
    -- saved fold up instead of replacing it
    scan(500)
    assert.equal(first, store.fold.at)
    assert.same({ first }, store.foldAts)
  end)

  it("keeps the last eight, oldest out", function()
    for _ = 1, 10 do
      store.requestedAt = nil
      now = now + 3 * 3600
      scan(500)
      assert.is_true(#store.foldAts <= 8)
    end
    assert.equal(8, #store.foldAts)
    assert.equal(now, store.foldAts[8])
    assert.equal(now - 7 * 3 * 3600, store.foldAts[1])
  end)

  it("remembers a stamp once", function()
    local db = { foreverScan = { fold = { at = 500, region = 90, items = {} } } }
    GC.ForeverScan.Init(db, driver())
    GC.ForeverScan.Init(db, driver())
    assert.same({ 500 }, db.foreverScan.foldAts)
  end)

  it("starts from the fold the save already holds, and from a save with none", function()
    local db = { foreverScan = { fold = { at = 500, region = 90, items = {} } } }
    GC.ForeverScan.Init(db, driver())
    assert.same({ 500 }, db.foreverScan.foldAts)
    local fresh = {}
    GC.ForeverScan.Init(fresh, driver())
    assert.is_nil(fresh.foreverScan.foldAts)
  end)

  it("mends a save whose list is not a list, and ignores a stamp that is not a stamp", function()
    local db = { foreverScan = { foldAts = "junk", fold = { at = 500, region = 90, items = {} } } }
    GC.ForeverScan.Init(db, driver())
    assert.same({ 500 }, db.foreverScan.foldAts)
    db.foreverScan.fold.at = "soon"
    GC.ForeverScan.Init(db, driver())
    assert.same({ 500 }, db.foreverScan.foldAts)
  end)

  it("never writes the key on retail", function()
    local db = {}
    GC.ForeverScan.Init(db, { passport = function() return { interface = 120100, region = 3, realm = "Silvermoon" } end })
    assert.is_nil(db.foreverScan)
  end)
end)

describe("the impact line's wiring", function()
  local init, data, scanSrc
  before_each(function()
    init = read("GoldCap/Core/Init.lua")
    data = read("GoldCap/Core/Data.lua")
    scanSrc = read("GoldCap/Core/ForeverScan.lua")
  end)

  it("speaks only at the loading screen, right after the first-run intro", function()
    local first, last = init:find("GC.ForeverScan.SayImpact()", 1, true)
    assert.truthy(first)
    assert.is_nil(init:find("GC.ForeverScan.SayImpact()", last + 1, true), "one call site")
    local world = assert(init:find('elseif event == "PLAYER_ENTERING_WORLD" then', 1, true))
    local nextEvent = assert(init:find('elseif event == "GET_ITEM_INFO_RECEIVED" then', 1, true))
    local intro = assert(init:find("GC.ForeverScan.MaybeIntro()", 1, true))
    assert.is_true(world < intro and intro < first and first < nextEvent)
  end)

  it("adopts the key only inside AdoptAppData's Forever branch, before its return", function()
    local fnStart = assert(data:find("function GC.Data.AdoptAppData()", 1, true))
    local adopt = assert(data:find("GC.ForeverScan.AdoptImpact(forever.foreverImpact)", fnStart, true))
    local ret = assert(data:find("\n    return\n", fnStart, true))
    local retailRead = assert(data:find("adoptImportString(appData)", fnStart, true))
    assert.is_true(fnStart < adopt and adopt < ret and ret < retailRead)
    assert.is_nil(data:find("foreverImpact", retailRead, true), "retail never reads the key")
  end)

  it("keeps the store's stamps behind the Forever store, and asks the game for nothing new", function()
    assert.truthy(scanSrc:find("rememberAt(s, s.fold.at)", 1, true))
    assert.truthy(scanSrc:find("rememberAt(db.foreverScan, db.foreverScan.fold.at)", 1, true))
    local say = assert(scanSrc:find("function GC.ForeverScan.SayImpact()", 1, true))
    assert.truthy(scanSrc:find("GC.ForeverScan.Store()", say, true))
  end)
end)
