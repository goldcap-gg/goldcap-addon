local helper = require("spec.spec_helper")

local function getUpvalue(fn, wanted)
  for i = 1, math.huge do
    local name, value = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then return value end
  end
  error("missing upvalue " .. wanted)
end

local function setUpvalue(fn, wanted, value)
  for i = 1, math.huge do
    local name = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then debug.setupvalue(fn, i, value); return end
  end
  error("missing upvalue " .. wanted)
end

local function ids(deals)
  local out = {}
  for _, deal in ipairs(deals) do out[#out + 1] = deal.itemID end
  return out
end

local function loadHarness()
  local starts, resumes, stops, autoEvents = {}, 0, 0, {}
  local scanner = { scanned = 0, cycles = 0 }
  function scanner:Start(targets)
    local copy = {}
    for i, itemID in ipairs(targets) do copy[i] = itemID end
    starts[#starts + 1] = copy
  end
  function scanner:Resume() resumes = resumes + 1 end
  function scanner:Stop() stops = stops + 1 end

  local autoState = "OFF"
  local GC = {
    Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } } },
    AutoScan = {
      New = function(_, actions)
        return {
          Input = function(_, event)
            autoEvents[#autoEvents + 1] = event
            if event == "toggleOn" then autoState = "IDLE" end
            if event == "toggleOff" then
              if autoState == "SCANNING" then actions.abortScan() end
              autoState = "OFF"
            end
          end,
          State = function() return autoState end,
          PauseReasons = function() return {} end,
          Tick = function() end,
        }
      end,
    },
    Data = {
      GetItemValue = function() return nil end,
      GetWatchlist = function() return { 91, 92 } end,
    },
    db = { settings = { sniper = {} } },
    SniperDecision = {
      Evaluate = function()
        return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } }
      end,
    },
    Sell = { Reset = function() end },
    Print = function() end,
    session = { buys = 0 },
  }
  helper.loadModule("Core/FullScan.lua", GC)
  helper.loadModule("UI/SniperFrame.lua", GC)

  local createFrame = getUpvalue(GC.Sniper.Toggle, "createFrame")
  local startLiveMode = GC.Sniper._StartLiveMode
  local startScanning = getUpvalue(startLiveMode, "startScanning")
  local stopScanning = getUpvalue(createFrame, "stopScanning")
  local onFullScanClick = getUpvalue(createFrame, "onFullScanClick")
  local startFullScan = getUpvalue(onFullScanClick, "startFullScan")
  local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
  local refreshRows = getUpvalue(clearDeals, "refreshRows")
  local createRow = getUpvalue(refreshRows, "createRow")
  local buildRowCell = getUpvalue(createRow, "buildRowCell")
  local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
  local openDialog = getUpvalue(onBuyClick, "openDialog")
  local startRequery = getUpvalue(openDialog, "startRequery")
  local driver = getUpvalue(startRequery, "driver")

  GC.Sniper.scanner = scanner
  return {
    GC = GC,
    scanner = scanner,
    starts = starts,
    resumeCount = function() return resumes end,
    stopCount = function() return stops end,
    autoEvents = autoEvents,
    startScanning = startScanning,
    stopScanning = stopScanning,
    startLiveMode = startLiveMode,
    startFullScan = startFullScan,
    driver = driver,
  }
end

describe("Sniper Auto-to-Live continuity", function()
  it("starts Live on the visible Auto candidates without clearing them", function()
    local h = loadHarness()
    local original = {
      { itemID = 10, tier = "GOOD", profit = 500, unitPrice = 100, qty = 1 },
      { itemID = 20, tier = "WATCH", profit = 200, unitPrice = 300, qty = 1 },
    }
    setUpvalue(h.startScanning, "scanDeals", original)

    h.startScanning()

    assert.same({ 10, 20 }, h.starts[1])
    assert.same({ 10, 20 }, ids(getUpvalue(h.startScanning, "scanDeals")))
    assert.equal("fullscan", getUpvalue(h.startScanning, "mode"))
  end)

  it("falls back to the imported watchlist only when no scan candidates exist", function()
    local h = loadHarness()
    setUpvalue(h.startScanning, "scanDeals", {})

    h.startScanning()

    assert.same({ 91, 92 }, h.starts[1])
    assert.equal("watchlist", getUpvalue(h.startScanning, "mode"))
  end)

  it("updates, removes, and re-adds only the observed Auto candidate", function()
    local h = loadHarness()
    local first = { itemID = 10, tier = "GOOD", profit = 500, unitPrice = 100, qty = 1 }
    local keep = { itemID = 20, tier = "WATCH", profit = 200, unitPrice = 300, qty = 1 }
    setUpvalue(h.startScanning, "scanDeals", { first, keep })
    h.startScanning()

    local raised = { itemID = 10, tier = "WATCH", profit = 250, unitPrice = 150, qty = 1 }
    h.driver.onObservation(10, raised)
    assert.same({ 10, 20 }, ids(getUpvalue(h.startScanning, "scanDeals")))
    h.driver.onObservation(10, nil)
    assert.same({ 20 }, ids(getUpvalue(h.startScanning, "scanDeals")))
    h.driver.onObservation(10, raised)
    assert.same({ 10, 20 }, ids(getUpvalue(h.startScanning, "scanDeals")))
  end)

  it("resumes the exact Live monitor after Check without a fresh Start or list clear", function()
    local h = loadHarness()
    local original = {
      { itemID = 10, tier = "GOOD", profit = 500, unitPrice = 100, qty = 1 },
      { itemID = 20, tier = "WATCH", profit = 200, unitPrice = 300, qty = 1 },
    }
    setUpvalue(h.startScanning, "scanDeals", original)
    setUpvalue(h.GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    h.startScanning()
    h.stopScanning()
    local attempt = { itemID = 10 }
    h.GC.Sniper._pausedLiveRequery = attempt

    h.GC.Sniper._ResumePausedLiveRequery(attempt)

    assert.equal(1, #h.starts)
    assert.equal(1, h.resumeCount())
    assert.same({ 10, 20 }, ids(getUpvalue(h.startScanning, "scanDeals")))
  end)

  it("does not resume paused Live after Scan takes browse traffic ownership", function()
    _G.C_AuctionHouse = { IsThrottledMessageSystemReady = function() return false end }
    local h = loadHarness()
    setUpvalue(h.GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    h.startScanning()
    h.stopScanning()
    local attempt = { itemID = 91 }
    h.GC.Sniper._pausedLiveRequery = attempt

    h.startFullScan()
    h.GC.Sniper._ResumePausedLiveRequery(attempt)

    assert.equal(0, h.resumeCount())
    assert.equal(1, #h.starts)
    _G.C_AuctionHouse = nil
  end)

  it("does not resume paused Live after Auto takes scan ownership", function()
    _G.GetTime = function() return 100 end
    local h = loadHarness()
    local feedAuto = getUpvalue(h.startLiveMode, "feedAuto")
    setUpvalue(h.GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    h.startScanning()
    h.stopScanning()
    local attempt = { itemID = 91 }
    h.GC.Sniper._pausedLiveRequery = attempt

    feedAuto("toggleOn")
    h.GC.Sniper._ResumePausedLiveRequery(attempt)

    assert.equal(0, h.resumeCount())
    assert.equal(1, #h.starts)
    _G.GetTime = nil
  end)

  it("stops Auto before Live and stops Live before browse traffic", function()
    _G.GetTime = function() return 100 end
    _G.C_AuctionHouse = { IsThrottledMessageSystemReady = function() return false end }
    local h = loadHarness()
    local feedAuto = getUpvalue(h.startLiveMode, "feedAuto")
    feedAuto("toggleOn")

    h.startLiveMode()
    assert.equal("toggleOff", h.autoEvents[#h.autoEvents])
    assert.equal(1, #h.starts)

    h.startFullScan()
    assert.equal(2, h.stopCount())
    _G.GetTime, _G.C_AuctionHouse = nil, nil
  end)

  it("clears the active Live session on AH close but retains scan candidates", function()
    _G.GetTime = function() return 100 end
    local h = loadHarness()
    local original = {
      { itemID = 10, tier = "GOOD", profit = 500, unitPrice = 100, qty = 1 },
    }
    setUpvalue(h.startScanning, "scanDeals", original)
    setUpvalue(h.GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    h.startScanning()

    h.GC.Sniper.OnAuctionHouseClosed()

    assert.same({}, h.GC.Sniper._liveTargets)
    assert.is_false(h.GC.Sniper._liveTracksScanDeals)
    assert.same({ 10 }, ids(getUpvalue(h.startScanning, "scanDeals")))
    _G.GetTime = nil
  end)
end)
