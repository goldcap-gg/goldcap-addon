local helper = require("spec.spec_helper")

-- SniperFrame.lua's own wiring of the REAL Core/AutoScan.lua state machine to the browse full
-- scan (startFullScan -> C_AuctionHouse.SendBrowseQuery). Every other spec in this suite stubs
-- GC.AutoScan.New's Tick out entirely (see e.g. auto_verify_spec.lua/watch_loop_spec.lua's
-- loadSniper), so this file is the one place the actual `startScan` action -- the closure
-- assigned inside `autoScan = GC.AutoScan.New({}, { startScan = ... })` -- gets driven for
-- real. Exists to prove the auto-scan tick yields while the player is posting in Blizzard's
-- own default sell panel and resumes the moment they leave it. Confirmed live 2026-08-18: with
-- the window closed, this kept sending browse queries while the player tried to click Create
-- Auction, and every click failed with "You're doing that too fast" -- the shared request
-- throttle was being spent by this tick, not by the player's own action.
describe("Auto-scan tick, wired to the real AutoScan machine", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local browseSent

  local function loadSniper()
    browseSent = 0
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetMoney = function() return 10 * 1000 * 10000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.PlaySound = function() end
    _G.SOUNDKIT = { READY_CHECK = 8960, MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() browseSent = browseSent + 1 end,
    }

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
          gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } } },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return { status = "AVOID", buyable = false, reasons = {} } end,
        MarketFromValue = function() return {} end, ReasonText = function(t) return "reason:" .. tostring(t) end },
      FullScan = {},
      Print = function() end,
      db = { settings = { sniper = { sound = true, showRefused = false } } },
      AuctionHouseTab = { PlayerIsBusy = function() return false end },
      -- GC.Sniper.OnAuctionHouseShow's own _RefreshWatchSet() call reaches this -- only the
      -- I1 test below actually invokes OnAuctionHouseShow for real (every other test in this
      -- file drives autoScan/feedAuto/installSearchHooks directly), so it needs a live target
      -- list even though nothing here cares what it contains.
      WatchSet = { Select = function() return {} end },
    }
    helper.loadModule("Core/AutoScan.lua", GC) -- the real FSM, not the stub every other spec uses
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer, _G.C_AuctionHouse =
      nil, nil, nil, nil, nil, nil
    _G.AuctionHouseFrame, _G.AuctionHouseFrameDisplayMode, _G.hooksecurefunc = nil, nil, nil
  end)

  -- Reported from the game: the Auto button read "AUTO · SCANNING" and no scan ever ran. The
  -- machine advanced to SCANNING whatever this action did, and this action withholds the send
  -- while the player is working Blizzard's own panes -- so the machine sat in a state only a
  -- finished scan could leave, waiting for a scan that was never started.
  it("does not claim to be scanning when the send was withheld", function()
    local GC = loadSniper()
    local feedAuto = upvalue(GC.Sniper.OnAuctionHouseShow, "feedAuto")
    local autoScan = upvalue(feedAuto, "autoScan")
    GC.AuctionHouseTab.PlayerIsBusy = function() return true end

    autoScan:Input("toggleOn", 1000)
    autoScan:Tick(1000)
    assert.equal("WAITING", autoScan:State()) -- still waiting, because nothing was sent
    assert.equal(0, browseSent)

    -- And it retries by itself once the player is done, with no toggle and no other input:
    -- the settle deadline the withheld start re-armed comes round and the scan goes out.
    GC.AuctionHouseTab.PlayerIsBusy = function() return false end
    autoScan:Tick(1002)
    assert.equal("SCANNING", autoScan:State())
    assert.equal(1, browseSent)
  end)

  -- (fix round 2) Enum.AuctionHouseDisplayMode does not exist on the live client -- confirmed
  -- against Gethe/wow-ui-source, Interface/AddOns/Blizzard_AuctionHouseUI/Shared/
  -- Blizzard_AuctionHouseFrame.lua: the mode identifiers are keys of the plain Lua table
  -- AuctionHouseFrameDisplayMode (Buy/WoWTokenBuy/CommoditiesBuy/ItemBuy/CommoditiesSell/
  -- ItemSell/WoWTokenSell/Auctions), never an Enum -- so the old comparison always fell through
  -- to the degraded "pause + blind 0.5s resume" branch. With the real table available, the hook
  -- can tell Buy (the browse list, where background sniping is the product) from every other
  -- mode outright, no timer needed.
  it("the repaired mode hook pauses on any non-Buy mode and resumes on Buy, with no 0.5s timer", function()
    local GC = loadSniper()
    local show = GC.Sniper.OnAuctionHouseShow
    local feedAuto = upvalue(show, "feedAuto")
    local autoScan = upvalue(feedAuto, "autoScan")
    local installSearchHooks = upvalue(show, "installSearchHooks")

    local afterCalls = 0
    _G.C_Timer.After = function() afterCalls = afterCalls + 1 end
    _G.hooksecurefunc = function(target, method, fn)
      local original = target[method]
      target[method] = function(...)
        original(...)
        fn(...)
      end
    end
    _G.AuctionHouseFrameDisplayMode = { Buy = {}, ItemBuy = {}, CommoditiesBuy = {} }
    local ah = {}
    ah.SetDisplayMode = function(self, mode)
      if self.displayMode == mode then return end
      self.displayMode = mode
    end
    _G.AuctionHouseFrame = ah

    installSearchHooks()
    autoScan:Input("toggleOn", 1000)
    autoScan:Tick(1000)
    assert.equal("SCANNING", autoScan:State())
    -- startFullScan arms its own scan watchdog via C_Timer.After -- unrelated to the mode hook.
    -- Baseline AFTER that, so what's asserted below is the mode hook's own timer use, not this.
    local baseline = afterCalls

    ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.CommoditiesBuy)
    assert.equal("PAUSED", autoScan:State())
    assert.equal(baseline, afterCalls) -- no degraded-fallback timer once the mode table resolves

    ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
    assert.equal("WAITING", autoScan:State()) -- resumed straight into the settle countdown
    assert.equal(baseline, afterCalls)
  end)

  -- I1 (fix wave, sell honesty): AutoScan.lua's toggleOn wipes `reasons = {}` unconditionally,
  -- so an AUTO off->on cycle made while the Sell tab is showing used to lose the "sell" pause
  -- reason -- Auto would start browsing the AH again right underneath the pricing walk's own
  -- throttled search, exactly the starvation autoscan_wiring's other tests exist to prevent.
  -- GC.Sniper.OnAuctionHouseShow's own re-seed (fires on every AH open/reopen while
  -- cfg.sniper.auto is set) now re-feeds "pause:sell" whenever the module-local `view` is
  -- still "sell", the same way it already re-seeds "tab". `view` is driven through the real
  -- setView() (the same upvalue seam spec/toolbar_chrome_spec.lua uses for it) rather than
  -- poked directly, so this exercises the real shared cell every other SniperFrame.lua closure
  -- reads.
  local function widget()
    local w = { shown = false }
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:SetActive() end
    function w:SetText() end
    function w:SetTextColor() end
    return w
  end

  local function fakeToolbarFrame()
    local f = widget() -- OnAuctionHouseShow's own `not frame:IsShown()` reads the frame itself
    f.scroll, f.headerRow = widget(), widget()
    f.dealsChrome = { widget(), widget(), widget(), widget(), widget() }
    f.dealsTab, f.sellTab, f.soldTab = widget(), widget(), widget()
    f.status = widget()
    return f
  end

  -- A scan started by the Scan button has no pause reason anywhere that can stop it: the
  -- pause/resume feeds below reach Auto, and addPause does nothing at all while the machine is
  -- OFF. So a manual pass kept paging browse queries behind the Sell and Sold tabs -- taking
  -- throttle slots from the pricing walk and replacing the browse buffer under the player's
  -- own Browse pane.
  it("stops a manual pass when the player leaves the Deals tab", function()
    local GC = loadSniper()
    local show = GC.Sniper.OnAuctionHouseShow
    local createFrame = upvalue(show, "createFrame")
    local setView = upvalue(createFrame, "setView")
    set(setView, "frame", fakeToolbarFrame())

    GC.Sniper._bookPass:Start("classes")
    assert.is_true(GC.Sniper._bookPass:IsPaging())

    setView("sell")
    assert.is_false(GC.Sniper._bookPass:IsPaging())
  end)

  -- Auto's own pass is a different matter: it has a pause reason, it stands down for the Sell
  -- tab through the machine, and it resumes by itself afterwards. Aborting it here as well
  -- would throw away a pass that is going to be resumed anyway.
  it("leaves an Auto pass to the machine's own pause", function()
    local GC = loadSniper()
    local show = GC.Sniper.OnAuctionHouseShow
    local feedAuto = upvalue(show, "feedAuto")
    local autoScan = upvalue(feedAuto, "autoScan")
    local createFrame = upvalue(show, "createFrame")
    local setView = upvalue(createFrame, "setView")
    set(setView, "frame", fakeToolbarFrame())

    feedAuto("toggleOn")
    GC.Sniper._bookPass:Start("classes")
    setView("sold") -- Sold never queries the auction house, so Auto is not even paused for it
    assert.is_true(GC.Sniper._bookPass:IsPaging())
    assert.not_equal("OFF", autoScan:State())
  end)

  it("re-seeds the sell pause on an AUTO off->on cycle reached via OnAuctionHouseShow while Sell is showing", function()
    local GC = loadSniper()
    local show = GC.Sniper.OnAuctionHouseShow
    local feedAuto = upvalue(show, "feedAuto")
    local autoScan = upvalue(feedAuto, "autoScan")
    local createFrame = upvalue(show, "createFrame")
    local setView = upvalue(createFrame, "setView")
    set(setView, "frame", fakeToolbarFrame())

    GC.db.settings.sniper.auto = true
    GC.db.settings.sniper.autoOpen = false -- return before createFrame's own real widget build

    show() -- arms Auto for the first time (state OFF -> IDLE); nothing to switch views from yet
    setView("sell") -- player opens Sell while Auto is running: feedAuto("pause:sell") for real
    assert.is_true(autoScan:PauseReasons().sell)

    feedAuto("toggleOff") -- state -> OFF, reasons wiped
    show() -- re-open the AH with cfg.auto still true: toggleOn wipes reasons again

    assert.is_true(autoScan:PauseReasons().sell) -- re-seeded because `view` is still "sell"
  end)

  it("does not re-seed a sell pause on the same cycle when Deals is the active view", function()
    local GC = loadSniper()
    local show = GC.Sniper.OnAuctionHouseShow
    local feedAuto = upvalue(show, "feedAuto")
    local autoScan = upvalue(feedAuto, "autoScan")

    GC.db.settings.sniper.auto = true
    GC.db.settings.sniper.autoOpen = false

    show()
    feedAuto("toggleOff")
    show()

    assert.is_falsy(autoScan:PauseReasons().sell)
  end)
end)
