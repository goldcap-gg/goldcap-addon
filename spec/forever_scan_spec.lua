local helper = require("spec.spec_helper")

describe("ForeverScan", function()
  local GC, d, timers, notes, store, rows, now

  local function driver(over)
    local drv = {
      now = function() return now end,
      after = function(s, fn) timers[#timers + 1] = { s = s, fn = fn } end,
      replicate = function() d.replicated = (d.replicated or 0) + 1; return d.replicateOk ~= false end,
      numRows = function() return #rows end,
      rowInfo = function(i)
        local r = rows[i + 1]
        if not r then return nil end
        return r[1], r[2], r[3], r[4]
      end,
      isGear = function() return false end,
      startBrowse = function(kind) d.browse = kind; return d.browseAnswer end,
      store = function() return store end,
      passport = function()
        return { interface = 16001, build = "1.60.1.70009", region = 90, realm = "Forever", faction = "Horde" }
      end,
      notify = function(kind, a, b) notes[#notes + 1] = { kind, a, b } end,
    }
    for k, v in pairs(over or {}) do drv[k] = v end
    return drv
  end

  local function runAll()
    local guard = 0
    while #timers > 0 do
      guard = guard + 1
      assert(guard < 10000, "runaway timers")
      table.remove(timers, 1).fn()
    end
  end

  local function noted(kind)
    for _, n in ipairs(notes) do if n[1] == kind then return n end end
    return nil
  end

  local function dump(n, itemID)
    local out = {}
    for i = 1, n do out[i] = { itemID or (1000 + (i % 50)), 1, 100 + (i % 7), true } end
    return out
  end

  before_each(function()
    GC = helper.loadModule("Core/Game.lua")
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    d, timers, notes, store, rows, now = {}, {}, {}, {}, {}, 100000
  end)

  it("asks once on open, reads the dump at the first rows and saves the fold with its passport", function()
    local s = GC.ForeverScan.New(driver())
    rows = { { 2589, 20, 1340, true }, { 2589, 5, 350, true }, { 2592, 1, 5000, false } }
    assert.equal("started", s:OnAuctionHouseShow())
    assert.equal(1, d.replicated)
    assert.equal(now, store.requestedAt)
    runAll()
    assert.equal("classes", d.browse)            -- a full dump: the browse pass looks for commodities
    local fold = store.fold
    assert.equal("replicate", fold.source)
    assert.equal(3, fold.rows)
    assert.equal(2, fold.itemCount)
    assert.equal(16001, fold.interface)
    assert.equal(90, fold.region)
    assert.equal("Forever", fold.realm)
    assert.equal("Horde", fold.faction)
    assert.is_nil(fold.ruleset)
    assert.is_nil(fold.partial)
    assert.equal(now, fold.at)
    assert.equal(2, store.fold.v)
    local e = GC.ForeverFold.Decode(fold.items[2589])
    assert.equal(67, e.min); assert.equal(25, e.qty); assert.equal(2, e.lots)
    assert.equal("started", notes[1][1])
    local done = noted("done")
    assert.equal(3, done[2].rows); assert.is_true(done[2].replicated); assert.equal(1, done[2].pending)
    assert.is_false(s:IsBusy())
  end)

  it("reads at the event, in the same call, before any poll", function()
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    rows = { { 2589, 20, 1340, true } }
    s:OnReplicateUpdate()
    assert.truthy(store.fold)                    -- no timer had to run
  end)

  it("keeps what it read when the dump empties under it", function()
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    rows = dump(5000)
    s:OnReplicateUpdate()                        -- first batch (2000 rows) now
    rows = {}                                    -- the beta: gone by +10 s
    assert.has_no.errors(runAll)
    assert.is_true(store.fold.partial)
    assert.equal(2000, store.fold.rows)
    assert.equal("wide", d.browse)               -- partial: the browse pass covers everything
  end)

  it("treats a dump of exactly SUSPECT_CAP rows as a page and browses wide", function()
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    rows = dump(GC.ForeverScan.C.SUSPECT_CAP)
    runAll()
    assert.equal("wide", d.browse)
    assert.is_true(store.fold.partial)
  end)

  it("merges the browse pass: items the dump lacked, never a variant, never over a dump row", function()
    d.browseAnswer = "started"
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    rows = { { 2589, 20, 1340, true } }
    s:OnReplicateUpdate()
    assert.equal("browsing", s:State())
    assert.is_nil(store.fold)
    s:OnBrowsePassDone({
      [2589] = { floor = 60, qty = 10 },
      [3000] = { floor = 500, qty = 2 },
      [4000] = { floor = 9, qty = 1, variants = true },
    })
    runAll()                                     -- the browse timeout is a no-op now
    local fold = store.fold
    assert.equal("replicate+browse", fold.source)
    assert.equal(67, GC.ForeverFold.Decode(fold.items[2589]).min)
    assert.is_true(GC.ForeverFold.Decode(fold.items[3000]).browse)
    assert.is_nil(fold.items[4000])
  end)

  it("saves what it has when the browse pass never finishes", function()
    d.browseAnswer = "running"
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    rows = { { 2589, 20, 1340, true } }
    runAll()
    assert.is_true(store.fold.partial)
    assert.equal("replicate", store.fold.source)
  end)

  it("browses wide when the full scan never answers", function()
    d.browseAnswer = "started"
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    for _ = 1, GC.ForeverScan.C.WAIT_SECONDS / GC.ForeverScan.C.POLL_SECONDS do
      table.remove(timers, 1).fn()
    end
    assert.truthy(noted("noanswer"))
    assert.equal("wide", d.browse)
    s:OnBrowsePassDone({ [3000] = { floor = 500, qty = 2 } })
    assert.equal("browse", store.fold.source)
    assert.is_nil(store.fold.rows)
    assert.equal(1, noted("done")[2].items)
  end)

  it("says nothing was saved when neither the dump nor a browse pass came", function()
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    runAll()
    assert.is_nil(store.fold)
    assert.truthy(noted("done"))
    assert.is_nil(noted("done")[2])
  end)

  it("inside the throttle: silent on open, the button browses and says how long, across a reload", function()
    local first = GC.ForeverScan.New(driver())
    first:OnAuctionHouseShow()
    runAll()
    now = now + 60
    notes = {}
    local reloaded = GC.ForeverScan.New(driver())  -- same store: a /reload
    assert.equal("cooldown", reloaded:OnAuctionHouseShow())
    assert.equal(1, d.replicated)
    assert.same({}, notes)
    assert.equal("cooldown", reloaded:Request("button"))
    assert.equal(1, d.replicated)
    assert.same({ "cooldown", 15 }, { notes[1][1], notes[1][2] })
    assert.equal("wide", d.browse)
  end)

  -- Final review I3: pressing SCAN inside the cooldown starts a browse-only accumulator (an
  -- empty GC.ForeverFold.New(), not derived from the stored fold at all), and completing it must
  -- not replace the fuller fold the earlier full scan already saved.
  it("merges a cooldown SCAN's browse-only result into the stored fold instead of replacing it", function()
    local s = GC.ForeverScan.New(driver())
    rows = { { 2589, 20, 1340, true } }
    s:OnAuctionHouseShow()
    runAll()
    local original = store.fold
    assert.equal("replicate", original.source)
    assert.equal(1, original.rows)
    local originalMin = GC.ForeverFold.Decode(original.items[2589]).min
    now = now + 60
    d.browseAnswer = "started"
    assert.equal("cooldown", s:Request("button"))
    assert.equal("wide", d.browse)
    -- Priced at a much cheaper floor than the dump's own ladder -- proves the merge keeps the
    -- dump's own entry rather than letting a thin browse row overwrite it.
    s:OnBrowsePassDone({ [2589] = { floor = 1, qty = 500 }, [3000] = { floor = 250, qty = 4 } })
    runAll()
    local fold = store.fold
    assert.equal("replicate", fold.source)  -- honest: still the dump's own fold, only topped up
    assert.equal(1, fold.rows)              -- unchanged: no new replicate rows were read
    assert.is_true(fold.partial)
    assert.equal(2, fold.itemCount)
    assert.equal(originalMin, GC.ForeverFold.Decode(fold.items[2589]).min) -- kept, not overwritten
    local added = GC.ForeverFold.Decode(fold.items[3000])
    assert.equal(250, added.min)
    assert.is_true(added.browse)
  end)

  -- Parked N1 (plan 3b, final review): a cooldown SCAN's browse-only result must not merge into
  -- a full fold from a DIFFERENT auction house -- another realm inside the same account-wide
  -- 15-minute window, say -- or that realm's saved prices get stamped with this realm's passport.
  it("never merges a browse-only scan into another auction house's fold", function()
    local realm = "Forever"
    local s = GC.ForeverScan.New(driver({ passport = function()
      return { interface = 16001, build = "1.60.1.70009", region = 90, realm = realm, faction = "Horde" }
    end }))
    rows = { { 2589, 20, 1340, true } }
    s:OnAuctionHouseShow()
    runAll()
    assert.equal("Forever", store.fold.realm)
    realm = "Forever-PvP"
    now = now + 60
    d.browseAnswer = "started"
    assert.equal("cooldown", s:Request("button"))
    s:OnBrowsePassDone({ [3000] = { floor = 250, qty = 4 } })
    runAll()
    assert.equal("Forever-PvP", store.fold.realm)
    assert.equal("browse", store.fold.source)
    assert.is_nil(store.fold.items[2589])      -- realm A's price is not carried into realm B
    assert.equal(250, GC.ForeverFold.Decode(store.fold.items[3000]).min)
  end)

  it("never lets a stamp from the future lock the scan", function()
    store.requestedAt = now + 3600
    local s = GC.ForeverScan.New(driver())
    assert.equal("started", s:OnAuctionHouseShow())
  end)

  it("folds somebody else's dump while idle and stamps the throttle, asking nothing", function()
    store.requestedAt = now - 60
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()                       -- cooldown: idle, AH open
    rows = { { 2589, 20, 1340, true } }
    now = now + 5
    s:OnReplicateUpdate()
    runAll()
    assert.is_nil(d.replicated)
    assert.equal(now, store.requestedAt)
    assert.truthy(store.fold)
  end)

  it("ignores a dump while the auction house is closed", function()
    local s = GC.ForeverScan.New(driver())
    rows = { { 2589, 20, 1340, true } }
    s:OnReplicateUpdate()
    assert.is_nil(store.fold)
    assert.equal("idle", s:State())
  end)

  it("closing the auction house: nothing saved while waiting, the partial read saved while reading", function()
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    s:OnAuctionHouseClosed()
    assert.equal("idle", s:State())
    assert.is_nil(store.fold)
    runAll()                                     -- the stale poll does nothing
    store.requestedAt = nil
    s:OnAuctionHouseShow()
    rows = dump(5000)
    s:OnReplicateUpdate()
    s:OnAuctionHouseClosed()
    assert.is_true(store.fold.partial)
    assert.equal(2000, store.fold.rows)
    runAll()
    assert.equal(2000, store.fold.rows)
  end)

  it("answers busy while a scan runs, and closed when the auction house is shut", function()
    local s = GC.ForeverScan.New(driver())
    assert.equal("closed", s:Request("button"))
    assert.equal("closed", notes[1][1])
    s:OnAuctionHouseShow()
    assert.equal("busy", s:Request("button"))
  end)

  it("saves nothing from a dump of bid-only rows", function()
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    rows = { { 2589, 1, 0, true } }
    runAll()
    assert.is_nil(store.fold)
    assert.is_nil(noted("done")[2])
  end)

  it("replaces the previous fold whole", function()
    store.fold = { items = { [1] = "5,1,1,;0x1" } }
    local s = GC.ForeverScan.New(driver())
    s:OnAuctionHouseShow()
    rows = { { 2589, 20, 1340, true } }
    runAll()
    assert.is_nil(store.fold.items[1])
  end)

  describe("module", function()
    local db
    local function passport(interface, region, realm)
      return driver({ passport = function() return { interface = interface, region = region, realm = realm } end })
    end

    before_each(function()
      db = {}
    end)

    it("is off on retail: no store, no value, no key written", function()
      assert.is_false(GC.ForeverScan.Init(db, passport(120100, 3, "Silvermoon")))
      assert.is_false(GC.ForeverScan.Enabled())
      assert.is_nil(GC.ForeverScan.Store())
      assert.is_nil(GC.ForeverScan.ValueFor(2589))
      assert.is_nil(GC.ForeverScan.OnAuctionHouseShow())
      assert.is_nil(db.foreverScan)
      -- Retail never reads a fold, a saved one included, and never asks who the character is.
      db.foreverScan = { fold = { region = 3, realm = "Silvermoon", faction = "Horde", items = {} } }
      assert.is_nil(GC.ForeverScan.Fold())
      assert.is_nil(GC.ForeverScan._passport)
    end)

    it("answers from the fold of this region and realm, and only reads", function()
      GC.ForeverScan.Init(db, passport(16001, 90, "Forever"))
      db.foreverScan = { fold = { region = 90, realm = "Forever", at = 5000,
        items = { [2589] = "67,4060,31,;0x936 3x3000", [7] = "900,1,,gb;" } } }
      local lock = { __newindex = function() error("ValueFor wrote to the save") end }
      setmetatable(db.foreverScan, lock)
      setmetatable(db.foreverScan.fold, lock)
      setmetatable(db.foreverScan.fold.items, lock)
      local v = GC.ForeverScan.ValueFor(2589)
      assert.same({ mv = 67, min = 67, currentQty = 4060, listings = 31, ts = 5000, source = "scan",
        kind = "own_scan" }, v)
      local g = GC.ForeverScan.ValueFor(7)
      assert.is_true(g.gear); assert.is_true(g.browse); assert.is_nil(g.listings)
      assert.is_nil(GC.ForeverScan.ValueFor(1))
    end)

    it("answers nothing for another region's or another realm's fold", function()
      GC.ForeverScan.Init(db, passport(16001, 90, "Forever"))
      db.foreverScan = { fold = { region = 1, realm = "Forever", at = 1, items = { [2589] = "67,1,1,;0x1" } } }
      assert.is_nil(GC.ForeverScan.ValueFor(2589))
      db.foreverScan.fold.region = 90
      db.foreverScan.fold.realm = "Forever-PvP"
      assert.is_nil(GC.ForeverScan.ValueFor(2589))
    end)

    it("hands out the fold only for this region and realm, and saves fold version 2", function()
      GC.ForeverScan.Init(db, passport(16001, 90, "Forever"))
      assert.is_nil(GC.ForeverScan.Fold())
      db.foreverScan = { fold = { region = 90, realm = "Forever", at = 5000, items = { [7] = "900,1,,gb;" } } }
      assert.equal(5000, GC.ForeverScan.Fold().at)
      db.foreverScan.fold.realm = "Forever-PvP"
      assert.is_nil(GC.ForeverScan.Fold())
      GC.ForeverScan.Init(db, passport(120100, 3, "Silvermoon"))
      assert.is_nil(GC.ForeverScan.Fold())
    end)

    -- Final review I1 (plan 3c): GoldCapDB is account-wide, so an alt on the same realm but of
    -- the other faction must not read the first character's fold as its own market -- the same
    -- "one auction house" the writer's sameHouse keeps.
    it("hands out the fold only to a character of the faction that scanned it", function()
      local function as(faction)
        return driver({ passport = function()
          return { interface = 16001, region = 90, realm = "Forever", faction = faction }
        end })
      end
      GC.ForeverScan.Init(db, as("Horde"))
      db.foreverScan = { fold = { region = 90, realm = "Forever", faction = "Horde", at = 5000,
        items = { [2589] = "67,1,1,;0x1" } } }
      assert.equal(5000, GC.ForeverScan.Fold().at)
      GC.ForeverScan.Init(db, as("Alliance"))
      assert.is_nil(GC.ForeverScan.Fold())
      assert.is_nil(GC.ForeverScan.ValueFor(2589))
      -- The ruleset, once the client names one: the same rule.
      db.foreverScan.fold.faction, db.foreverScan.fold.ruleset = "Alliance", "hardcore"
      GC.ForeverScan._ruleset = "normal"
      assert.is_nil(GC.ForeverScan.Fold())
      GC.ForeverScan._ruleset = nil
      assert.equal(5000, GC.ForeverScan.Fold().at)
    end)

    -- The faction is read when the addon loads; a client that has not settled it yet answers
    -- nil there. The first read of the fold after it has settled holds it to the right one.
    it("learns the character's faction late when the client had not named it at load", function()
      local faction
      GC.ForeverScan.Init(db, driver({ passport = function()
        return { interface = 16001, region = 90, realm = "Forever", faction = faction }
      end }))
      db.foreverScan = { fold = { region = 90, realm = "Forever", faction = "Horde", at = 5000,
        items = { [2589] = "67,1,1,;0x1" } } }
      faction = "Alliance"
      assert.is_nil(GC.ForeverScan.Fold())
    end)

    it("creates its store only in Forever, and summarises it in English", function()
      GC.ForeverScan.Init(db, passport(16001, 90, "Forever"))
      assert.equal(db.foreverScan, GC.ForeverScan.Store())
      db.foreverScan.requestedAt = 900
      db.foreverScan.fold = { source = "replicate", rows = 1024, itemCount = 300, partial = true, at = 950,
        region = 90, realm = "Forever", faction = "Horde", items = {} }
      local text = table.concat(GC.ForeverScan.Summary(1000), "\n")
      assert.truthy(text:find("last full-scan request 100s ago", 1, true))
      assert.truthy(text:find("last fold replicate, 1024 rows, 300 items, partial, 50s old", 1, true))
      assert.truthy(text:find("scanner idle", 1, true))
    end)

    it("says the three first-run lines once, and only in Forever", function()
      local printed = {}
      GC.Print = function(m) printed[#printed + 1] = m end
      GC.L = setmetatable({}, { __index = function(_, k) return k end })
      GC.ForeverScan.Init(db, passport(120100, 3, "Silvermoon"))
      assert.is_false(GC.ForeverScan.MaybeIntro())
      assert.is_nil(db.foreverScan)
      GC.ForeverScan.Init(db, passport(16001, 90, "Forever"))
      assert.is_true(GC.ForeverScan.MaybeIntro())
      assert.equal(3, #printed)
      assert.equal("In WoW: Forever, GoldCap's prices come from your own auction house scans.", printed[1])
      assert.equal("Your scans stay on this computer. The GoldCap Companion shares them with goldcap.gg and brings everyone's prices back.",
        printed[3])
      assert.is_false(GC.ForeverScan.MaybeIntro())
      assert.equal(3, #printed)
      assert.is_true(db.foreverScan.introShown)
    end)

    it("keeps plan 3e's preferences in GoldCapDB.forever, created only in Forever", function()
      assert.is_false(GC.ForeverScan.Init(db, passport(120100, 3, "Silvermoon")))
      assert.is_nil(GC.ForeverScan.Prefs())
      assert.is_nil(GC.ForeverScan.Root())
      assert.is_nil(db.forever)
      GC.ForeverScan.Init(db, passport(16001, 90, "Forever"))
      local p = GC.ForeverScan.Prefs()
      assert.equal(db.forever, p)
      p.mountCost = 5
      assert.equal(5, GC.ForeverScan.Prefs().mountCost)
      assert.equal(db, GC.ForeverScan.Root())
    end)
  end)
end)
