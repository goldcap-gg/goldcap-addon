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

    it("defers a single Build off this frame, skipping the tooltip pass while the window is closed", function()
      load(16001)
      local buildCalls, skipSeen = 0, nil
      GC.ForeverUpgrades = {
        Current = function(skipUsable) buildCalls = buildCalls + 1; skipSeen = skipUsable; return { rows = {} } end,
        PrintCount = function() end,
      }
      local rendered = 0
      GC.ForeverUpgradesUI = { IsShown = function() return false end, Render = function() rendered = rendered + 1 end }
      GC.ForeverScan._QueueUpgradesUpdate()
      assert.equal(1, #timers)
      assert.equal(0, timers[1].s)
      assert.equal(0, buildCalls)              -- nothing runs before the timer fires
      timers[1].fn()
      assert.equal(1, buildCalls)
      assert.is_true(skipSeen)                 -- the tooltip pass is skipped: window is closed
      assert.equal(0, rendered)                -- and there is nothing to render
    end)

    it("builds once and hands that same result to both the chat count and the open window's render", function()
      load(16001)
      local buildCalls, skipSeen, sharedR = 0, nil, nil
      GC.ForeverUpgrades = {
        Current = function(skipUsable)
          buildCalls, skipSeen = buildCalls + 1, skipUsable
          sharedR = { rows = {} }
          return sharedR
        end,
      }
      local printedR, renderedR
      GC.ForeverUpgrades.PrintCount = function(r) printedR = r end
      GC.ForeverUpgradesUI = { IsShown = function() return true end, Render = function(r) renderedR = r end }
      GC.ForeverScan._QueueUpgradesUpdate()
      timers[1].fn()
      assert.equal(1, buildCalls)               -- one Build, not one per consumer
      assert.is_false(skipSeen)                  -- the window is open: the tooltip pass still runs
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

    it("builds the post queue with the Sell tab's own WoW: Forever options", function()
      assert.truthy(sell:find("GC.PostQueue.Build(positions, GC.Sell._QueueOpts())", 1, true))
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

    it("folds a finished browse pass and lets SCAN start the Forever scan", function()
      assert.truthy(sniper:find("GC.ForeverScan.OnBrowsePassDone(GC.Sniper._bookPass:Book())", 1, true))
      assert.truthy(sniper:find('GC.ForeverScan.Request("button")', 1, true))
      assert.truthy(sniper:find("function GC.Sniper.StartBrowsePass(kind)", 1, true))
    end)

    it("keeps scan work out of the Sell tab entirely", function()
      for _, word in ipairs({ "ForeverScan.Request", "OnReplicateUpdate", "StartBrowsePass", "ReplicateItems" }) do
        assert.is_nil(sell:find(word, 1, true), word)
      end
    end)
  end)
end)
