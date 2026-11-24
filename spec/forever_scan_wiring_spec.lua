local helper = require("spec.spec_helper")

local function read(path)
  local f = assert(io.open(path))
  local text = f:read("*a")
  f:close()
  return text
end

describe("WoW: Forever scan wiring", function()
  local GC, printed, timers, replicated, saved

  local function load(interface)
    saved = { GetBuildInfo = _G.GetBuildInfo, GetCurrentRegion = _G.GetCurrentRegion,
      GetRealmName = _G.GetRealmName, UnitFactionGroup = _G.UnitFactionGroup,
      C_AuctionHouse = _G.C_AuctionHouse, C_Timer = _G.C_Timer }
    printed, timers, replicated = {}, {}, 0
    _G.GetBuildInfo = function() return "1.60.1", "70009", "Sep 2026", interface end
    _G.GetCurrentRegion = function() return 90 end
    _G.GetRealmName = function() return "Forever" end
    _G.UnitFactionGroup = function() return "Horde" end
    _G.C_AuctionHouse = {
      ReplicateItems = function() replicated = replicated + 1 end,
      GetNumReplicateItems = function() return 0 end,
    }
    _G.C_Timer = { After = function(s, fn) timers[#timers + 1] = { s = s, fn = fn } end }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Game.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverScan.lua", GC)
    GC.Print = function(msg) printed[#printed + 1] = msg end
  end

  after_each(function()
    for k, v in pairs(saved or {}) do _G[k] = v end
    _G.GoldCap_AppData = nil
  end)

  it("with the real client driver: asks on open in Forever and says so", function()
    load(16001)
    local db = {}
    assert.is_true(GC.ForeverScan.Init(db))
    GC.ForeverScan.OnAuctionHouseShow()
    assert.equal(1, replicated)
    assert.equal("Scanning the auction house…", printed[1])
    assert.is_nil(db.foreverScan.fold)
    assert.is_number(db.foreverScan.requestedAt)
  end)

  -- A player, 2026-11-17: the scan stopped waiting for a browse pass that could not start behind
  -- their own search, and the pass stayed armed (spec/forever_scan_spec.lua). The real driver hands
  -- the scan's two questions about that pass to the window (UI/SniperFrame.lua).
  describe("with the real client driver, the scan's browse pass", function()
    it("is ended through GC.Sniper.StopBrowsePass when the wait for it runs out", function()
      load(16001)
      local stopped = 0
      GC.Sniper = {
        StartBrowsePass = function() return "started" end,
        StopBrowsePass = function() stopped = stopped + 1 end,
      }
      assert.is_true(GC.ForeverScan.Init({ foreverScan = { requestedAt = os.time() - 60 } }))
      GC.ForeverScan.OnAuctionHouseShow()
      assert.equal("cooldown", GC.ForeverScan.Request("button"))
      assert.is_true(GC.ForeverScan.IsBusy())
      for _, t in ipairs(timers) do
        if t.s == GC.ForeverScan.C.BROWSE_WAIT_SECONDS then t.fn() end
      end
      assert.equal(1, stopped)
      assert.is_false(GC.ForeverScan.IsBusy())
    end)

    it("is not asked for after a whole list while GC.Sniper.BrowseHeld says the player holds it back", function()
      load(16001)
      saved.C_Item = _G.C_Item
      _G.C_Item = { GetItemInfoInstant = function(itemID) return itemID, "Trade Goods", "Cloth", "", 0, 7, 5 end }
      local lots = { { 2589, 20, 1340 }, { 2589, 5, 350 }, { 2592, 1, 5000 } }
      _G.C_AuctionHouse.GetNumReplicateItems = function() return #lots end
      -- C_AuctionHouse.GetReplicateItemInfo's eighteen values: the count is the third, the buyout
      -- the tenth, the item the seventeenth, hasAllInfo the last.
      _G.C_AuctionHouse.GetReplicateItemInfo = function(i)
        local lot = lots[i + 1]
        return "name", 134400, lot[2], 1, true, 1, "", 1, 1, lot[3], 0, nil, nil, nil, nil, 0, lot[1], true
      end
      local asked = 0
      GC.Sniper = {
        BrowseHeld = function() return true end,
        StartBrowsePass = function() asked = asked + 1; return "started" end,
      }
      local db = {}
      assert.is_true(GC.ForeverScan.Init(db))
      GC.ForeverScan.OnAuctionHouseShow()
      table.remove(timers, 1).fn()               -- the first poll finds the list
      assert.equal(0, asked)
      assert.is_false(GC.ForeverScan.IsBusy())
      assert.equal(3, db.foreverScan.fold.rows)
      assert.is_nil(db.foreverScan.fold.partial)
    end)
  end)

  -- A list saved the moment it is read (the player's own pane holds the pass back) ends inside
  -- the second its last "reading the auction house" line holds the status line for, and the
  -- readout the scan's end writes was dropped behind that hold: "... do not close the auction
  -- house" stood there after the scan was over. The read's last line holds nothing.
  it("lets go of the status line with the read's last progress line", function()
    load(16001)
    local holds = {}
    GC.Sniper = {
      _ScanWords = function(text) return text end,
      SetScanStatus = function(_, hold) holds[#holds + 1] = hold end,
    }
    GC.ForeverScan._Notify("progress", 2000, 2500)
    GC.ForeverScan._Notify("progress", 2500, 2500)
    assert.same({ 1, 0 }, holds)
  end)

  -- The client hands the list over in stages, and each later one starts the read over: while
  -- stages keep coming the line says the list is still arriving, then reads N of M.
  it("says the list is still arriving while its stages come, by the table", function()
    load(16001)
    local S = GC.ForeverScan.C.STAGE_SETTLE_SECONDS
    local cases = {
      -- stages, readIndex, total, now, shown -> wording, N
      { name = "the first stage, just come", { 10 }, 2400, 111616, 10.5, {}, "receiving", 111616 },
      { name = "the first stage, settled", { 10 }, 2400, 111616, 10 + S, {}, "reading", 2400 },
      { name = "a later stage restarts the read", { 10, 11 }, 50, 146432, 12, { receiving = 111616 },
        "receiving", 146432 },
      { name = "a later stage after reading was shown", { 10, 20 }, 300, 327655, 20 + S,
        { receiving = 146432, reading = 60000 }, "reading", 60000 },
      { name = "the restarted read catches up", { 10, 20 }, 124600, 327655, 30, { reading = 60000 },
        "reading", 124600 },
      { name = "a later stage with fewer rows", { 10, 11 }, 0, 100000, 11.5, { receiving = 146432 },
        "receiving", 146432 },
      { name = "never past the lots there are", { 10 }, 500, 1000, 20, { reading = 5000 }, "reading", 1000 },
      { name = "no stage noted", {}, 5, 10, 0, {}, "reading", 5 },
    }
    for _, c in ipairs(cases) do
      local wording, n = GC.ForeverScan.ProgressLine(c[1], c[2], c[3], c[4], c[5])
      assert.equal(c[6], wording, c.name)
      assert.equal(c[7], n, c.name)
    end
  end)

  it("replays the stages of 2026-11-24 on the board line, its N never going back", function()
    load(16001)
    local now, lines = 0, {}
    local getTime = _G.GetTime
    _G.GetTime = function() return now end
    GC.Sniper = { _ScanWords = function(text) return text end,
      SetScanStatus = function(text) lines[#lines + 1] = text end }
    GC.ForeverScan._Notify("started")
    local steps = { { 0, 2400, 111616 }, { 0.5, 2450, 146432 }, { 1, 2300, 327655 }, { 1.5, 40000, 327655 },
      { 3.5, 124600, 327655 }, { 4, 327655, 327655 } }
    for _, s in ipairs(steps) do
      now = s[1]
      GC.ForeverScan._Notify("progress", s[2], s[3])
    end
    _G.GetTime = getTime
    assert.same({
      "Scanning the auction house…",
      "receiving the auction house list: 111616 lots so far",
      "receiving the auction house list: 146432 lots so far",
      "receiving the auction house list: 327655 lots so far",
      "receiving the auction house list: 327655 lots so far",
      "reading the auction house: 124600 of 327655 lots",
      "reading the auction house: 327655 of 327655 lots",
    }, lines)
  end)

  it("starts the line over for a new list that came with no word of the last one's end", function()
    load(16001)
    local now, lines = 0, {}
    local getTime = _G.GetTime
    _G.GetTime = function() return now end
    GC.Sniper = { _ScanWords = function(text) return text end,
      SetScanStatus = function(text) lines[#lines + 1] = text end }
    GC.ForeverScan._Notify("progress", 9000, 10000)
    now = 10
    GC.ForeverScan._Notify("progress", 10000, 10000)
    now = 20
    GC.ForeverScan._Notify("progress", 100, 5000)
    now = 30
    GC.ForeverScan._Notify("progress", 200, 5000)
    _G.GetTime = getTime
    assert.same({
      "receiving the auction house list: 10000 lots so far",
      "reading the auction house: 10000 of 10000 lots",
      "receiving the auction house list: 5000 lots so far",
      "reading the auction house: 200 of 5000 lots",
    }, lines)
  end)

  describe("post-scan chat block", function()
    local folds
    local function done(rows, partial)
      GC.ForeverScan._Notify("done", { rows = rows, items = 10, replicated = true, partial = partial })
    end
    local function countLine(text)
      local n = 0
      for _, m in ipairs(printed) do if m == text then n = n + 1 end end
      return n
    end
    before_each(function()
      load(16001)
      folds = 0
      GC.Sniper = { OnForeverFold = function() folds = folds + 1 end }
    end)

    it("prints a full read at once", function()
      done(54139, false)
      assert.equal("54139 lots scanned and saved", printed[1])
      assert.equal(0, #timers)
      assert.equal(1, folds)
    end)

    it("holds a partial read for the grace period, then prints it once", function()
      done(2048, true)
      assert.equal(0, #printed)
      assert.equal(1, folds) -- the refresh is never delayed
      assert.equal(1, #timers)
      timers[1].fn()
      assert.equal("2048 lots scanned and saved", printed[1])
      assert.equal(1, countLine("2048 lots scanned and saved"))
    end)

    it("a full read inside the grace period replaces the held block: printed once, with its numbers", function()
      done(2048, true)
      done(54139, false)
      assert.equal("54139 lots scanned and saved", printed[1])
      timers[1].fn() -- the stale timer fires and says nothing
      assert.equal(1, #printed)
      assert.equal(2, folds)
    end)

    it("a second partial read supersedes the first", function()
      done(2048, true)
      done(3072, true)
      timers[1].fn()
      assert.equal(0, #printed)
      timers[2].fn()
      assert.equal(1, #printed)
      assert.equal("3072 lots scanned and saved", printed[1])
    end)

    it("stays busy while a partial read's summary is held, and not after", function()
      GC.ForeverScan.Init({})
      assert.is_false(GC.ForeverScan.IsBusy())
      done(2048, true)
      assert.is_true(GC.ForeverScan.IsBusy())
      timers[1].fn()
      assert.is_false(GC.ForeverScan.IsBusy())
    end)

    -- A dump stage that comes while the scan browses is not read (Core/ForeverScan.lua's
    -- OnReplicateUpdate), so once the browse pass is given up no fuller read is coming to wait for.
    it("prints a partial read at once and is free when its browse pass was given up", function()
      GC.ForeverScan.Init({})
      GC.ForeverScan._Notify("done", { rows = 2048, items = 10, replicated = true, partial = true, givenUp = true })
      assert.equal("2048 lots scanned and saved", printed[1])
      assert.equal(0, #timers)
      assert.is_false(GC.ForeverScan.IsBusy())
    end)

    it("a full read ends the hold at once", function()
      GC.ForeverScan.Init({})
      done(2048, true)
      done(54139, false)
      assert.is_false(GC.ForeverScan.IsBusy())
    end)

    it("repaints the toolbar on the scanner's edges", function()
      local repaints = 0
      GC.Sniper.RepaintScanState = function() repaints = repaints + 1 end
      GC.ForeverScan.Init({})
      GC.ForeverScan.OnAuctionHouseShow()
      assert.is_true(repaints >= 1)
      local before = repaints
      done(54139, false)
      assert.is_true(repaints > before)
    end)

    it("a new scan cancels a held block", function()
      done(2048, true)
      GC.ForeverScan._Notify("started")
      timers[1].fn()
      assert.equal(1, #printed)
      assert.equal("Scanning the auction house…", printed[1])
    end)
  end)

  describe("hints are said once a session", function()
    local function said(text)
      local n = 0
      for _, m in ipairs(printed) do if m:find(text, 1, true) then n = n + 1 end end
      return n
    end
    local function scanDone()
      GC.ForeverScan._SayDone({ rows = 1000, items = 10, replicated = true })
    end
    before_each(function()
      load(16001)
      GC.ForeverScan.Init({})
      GC.Data = { CompanionShares = function() return true end, GetItemValue = function() return nil end }
      GC.ForeverValue = { PrintBags = function(_, s)
        if s then
          if s.bags ~= "bags" then GC.Print("bags") end
          s.bags = "bags"
          if not s.postHint then GC.Print("POST hint"); s.postHint = true end
        else
          GC.Print("bags"); GC.Print("POST hint")
        end
      end }
    end)

    it("keeps the result line every time and the static lines once", function()
      scanDone(); scanDone(); scanDone()
      assert.equal(3, said("lots scanned and saved"))
      assert.equal(1, said("bags"))
      assert.equal(1, said("POST hint"))
      assert.equal(1, said("Shared with goldcap.gg"))
    end)
  end)

  it("on retail: no scan, no key in the save", function()
    load(120100)
    local db = {}
    assert.is_false(GC.ForeverScan.Init(db))
    GC.ForeverScan.OnAuctionHouseShow()
    assert.equal(0, replicated)
    assert.is_nil(db.foreverScan)
  end)

  -- There is no Forever Companion or upload in this build (final review I1): a scan always says
  -- it stayed here, whether or not GoldCap_AppData happens to be sitting in this install.
  it("always says the scan stayed here -- there is no Forever Companion upload yet", function()
    load(16001)
    _G.GoldCap_AppData = { region = "eu" }
    GC.ForeverScan._SayDone({ rows = 8412, items = 900, replicated = true })
    GC.ForeverScan._SayDone({ items = 300, replicated = false })
    GC.ForeverScan._SayDone(nil)
    assert.equal("8412 lots scanned and saved", printed[1])
    assert.equal("300 items scanned and saved", printed[2])
    assert.equal("The scan found nothing to save", printed[3])
  end)

  -- Final review re-review (2026-09-27): PrintCount and RefreshIfShown each ran their own
  -- Core/ForeverUpgrades.lua Build synchronously on the scan-completion frame, and twice over
  -- when the upgrades window happened to be open. _QueueUpgradesUpdate replaces both call sites.
  describe("_QueueUpgradesUpdate", function()
    it("does nothing without Core/ForeverUpgrades.lua loaded", function()
      load(16001)
      GC.ForeverScan._QueueUpgradesUpdate()
      assert.equal(0, #timers)
    end)

    it("defers a single Build off this frame, skipping the tooltip pass while the HERO tab is not up", function()
      load(16001)
      local buildCalls, skipSeen = 0, nil
      GC.ForeverUpgrades = {
        Current = function(skipUsable) buildCalls = buildCalls + 1; skipSeen = skipUsable; return { slots = {} } end,
        PrintCount = function() end,
      }
      local rendered = 0
      GC.Hero = { IsShown = function() return false end, Render = function() rendered = rendered + 1 end }
      GC.ForeverScan._QueueUpgradesUpdate()
      assert.equal(1, #timers)
      assert.equal(0, timers[1].s)
      assert.equal(0, buildCalls)              -- nothing runs before the timer fires
      timers[1].fn()
      assert.equal(1, buildCalls)
      assert.is_true(skipSeen)                 -- the tooltip pass is skipped: the tab is not up
      assert.equal(0, rendered)                -- and there is nothing to render
    end)

    it("builds once and hands that same result to both the chat count and the HERO tab's render", function()
      load(16001)
      local buildCalls, skipSeen, sharedR = 0, nil, nil
      GC.ForeverUpgrades = {
        Current = function(skipUsable)
          buildCalls, skipSeen = buildCalls + 1, skipUsable
          sharedR = { slots = {} }
          return sharedR
        end,
      }
      local printedR, renderedR
      GC.ForeverUpgrades.PrintCount = function(r) printedR = r end
      GC.Hero = { IsShown = function() return true end, Render = function(r) renderedR = r end }
      GC.ForeverScan._QueueUpgradesUpdate()
      timers[1].fn()
      assert.equal(1, buildCalls)               -- one Build, not one per consumer
      assert.is_false(skipSeen)                  -- the tab is up: the tooltip pass still runs
      assert.equal(sharedR, printedR)
      assert.equal(sharedR, renderedR)
    end)
  end)

  describe("source wiring", function()
    local init, sniper, sell
    before_each(function()
      init = read("GoldCap/Core/Init.lua")
      sniper = read("GoldCap/UI/SniperFrame.lua")
      sell = helper.sellSource()
    end)

    it("registers the dump event and the scan command only inside a Forever gate", function()
      local reg = init:find('RegisterEvent%("REPLICATE_ITEM_LIST_UPDATE"%)')
      assert.truthy(reg)
      assert.truthy(init:sub(reg - 300, reg):find("IsForever", 1, true))
      local slash = init:find("GC.slashHandlers.scan", 1, true)
      assert.truthy(slash)
      assert.truthy(init:sub(slash - 300, slash):find("IsForever", 1, true))
      local bags = init:find("GC.slashHandlers.bags", 1, true)
      assert.truthy(bags)
      assert.truthy(init:sub(bags - 300, bags):find("IsForever", 1, true))
    end)

    -- "The same as SCAN on the Deals tab": the command takes the Buy list back from the player's
    -- own search too, and starts nothing while a scan runs.
    it("runs /gc scan through the Deals tab's own press of SCAN", function()
      local slash = assert(init:find("GC.slashHandlers.scan =", 1, true))
      assert.truthy(init:sub(slash, slash + 200):find("GC.Sniper._ForeverScanPress()", 1, true))
    end)

    it("builds the post queue with the Sell tab's own WoW: Forever options", function()
      assert.truthy(sell:find("GC.PostQueue.Build(S.positions, GC.Sell._QueueOpts())", 1, true))
    end)

    it("routes the dump event, the auction house's open and close, and the load", function()
      assert.truthy(init:find('event == "REPLICATE_ITEM_LIST_UPDATE"', 1, true))
      assert.truthy(init:find("GC.ForeverScan.OnReplicateUpdate()", 1, true))
      local show = init:find("GC.Sniper.OnAuctionHouseShow()", 1, true)
      assert.truthy(init:find("GC.ForeverScan.OnAuctionHouseShow()", show, true))
      local _, closes = init:gsub("GC%.ForeverScan%.OnAuctionHouseClosed%(%)", "")
      assert.equal(2, closes)
      assert.truthy(init:find("GC.ForeverScan.Init(GC.db)", 1, true))
    end)

    it("finishes a scan still saving at logout, before the game writes the save", function()
      local from = assert(init:find('event == "PLAYER_LOGOUT" then', 1, true))
      local branch = init:sub(from, assert(init:find("\n  end\nend)", from, true)))
      assert.truthy(branch:find("GC.ForeverScan.OnLogout()", 1, true))
    end)

    -- Review, 2026-11-06: the Deals board's unsure items are asked again where the client can ask.
    it("tells the Deals board the auction house opened, after the scan hears it", function()
      local scan = init:find("GC.ForeverScan.OnAuctionHouseShow()", 1, true)
      assert.truthy(init:find("GC.ForeverDeals.OnAuctionHouseShow()", scan, true))
    end)

    it("folds a finished browse pass and lets SCAN start the Forever scan", function()
      assert.truthy(sniper:find("GC.ForeverScan.OnBrowsePassDone(GC.Sniper._bookPass:Book())", 1, true))
      assert.truthy(sniper:find('GC.ForeverScan.Request("button")', 1, true))
      assert.truthy(sniper:find("function GC.Sniper.StartBrowsePass(kind)", 1, true))
    end)

    it("folds a given-up browse pass at once", function()
      assert.truthy(sniper:find("GC.ForeverScan.OnBrowsePassAbandoned(GC.Sniper._bookPass:Book())", 1, true))
    end)

    it("keeps scan work out of the Sell tab entirely", function()
      for _, word in ipairs({ "ForeverScan.Request", "OnReplicateUpdate", "StartBrowsePass", "ReplicateItems" }) do
        assert.is_nil(sell:find(word, 1, true), word)
      end
    end)
  end)
end)
