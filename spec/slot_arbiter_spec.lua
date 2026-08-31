local helper = require("spec.spec_helper")

describe("Search slot arbiter", function()
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

  local sent

  local function load()
    sent = {}
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
      Scanner = { New = function() return {} end },
      Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
        ReasonText = function(t) return tostring(t) end },
      FullScan = {}, WatchSet = {}, Print = function() end,
      db = { settings = { sniper = { sound = false } } },
    }
    helper.loadModule("UI/SniperFrame.lua", GC)
    -- A fake watch scanner whose only job is to record that it was handed a slot.
    local watch = { hungry = true }
    function watch:Wants() return self.hungry end
    function watch:OnSystemReady() sent[#sent + 1] = "watch" end
    GC.Sniper.scanner = watch
    set(GC.Sniper.OnThrottleReady, "sendBrowsePage", function() sent[#sent + 1] = "page" end)
    set(GC.Sniper.OnThrottleReady, "pendingBrowsePage", true)
    return GC, watch
  end

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer, _G.GetCoinTextureString = nil, os.time, nil, nil
  end)

  it("splits contested slots evenly, watch first", function()
    local GC = load()
    for _ = 1, 6 do
      set(GC.Sniper.OnThrottleReady, "pendingBrowsePage", true)
      GC.Sniper.OnThrottleReady()
    end
    assert.same({ "watch", "page", "watch", "page", "watch", "page" }, sent)
  end)

  it("leaves no slot idle when only one consumer is hungry", function()
    local GC, watch = load()
    watch.hungry = false
    for _ = 1, 3 do
      set(GC.Sniper.OnThrottleReady, "pendingBrowsePage", true)
      GC.Sniper.OnThrottleReady()
    end
    assert.same({ "page", "page", "page" }, sent)

    watch.hungry = true
    set(GC.Sniper.OnThrottleReady, "pendingBrowsePage", false)
    GC.Sniper.OnThrottleReady()
    GC.Sniper.OnThrottleReady()
    assert.same({ "page", "page", "page", "watch", "watch" }, sent)
  end)

  it("stands the watch loop down when the Deals view is not on screen, so Sell isn't starved", function()
    local GC = load()
    set(GC.Sniper.OnThrottleReady, "view", "sell")
    for _ = 1, 3 do
      set(GC.Sniper.OnThrottleReady, "pendingBrowsePage", true)
      GC.Sniper.OnThrottleReady()
    end
    -- With the watch loop stood down, browse paging alone takes every slot -- none go to
    -- "watch", and none are left idle for GC.Sell.OnThrottleReady to starve on next.
    assert.same({ "page", "page", "page" }, sent)

    set(GC.Sniper.OnThrottleReady, "view", "deals")
    set(GC.Sniper.OnThrottleReady, "pendingBrowsePage", true)
    GC.Sniper.OnThrottleReady()
    assert.same({ "page", "page", "page", "watch" }, sent) -- watch resumes once Deals is back up
  end)

  it("gives a parked Check the slot ahead of both", function()
    local GC = load()
    local searched = {}
    set(GC.Sniper.OnThrottleReady, "driver", { sendSearch = function(id) searched[#searched + 1] = id end })
    local attempt = { itemID = 42, token = 1, row = {}, deal = { itemID = 42 } }
    upvalue(GC.Sniper.OnThrottleReady, "pendingRequerySend")[42] = attempt
    set(GC.Sniper.OnThrottleReady, "isCurrentRequeryAttempt", function() return true end)

    GC.Sniper.OnThrottleReady()
    assert.same({ 42 }, searched)
    assert.same({}, sent)
  end)

  it("only lets the watch loop send inside its own grant", function()
    local GC = load()
    local mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan
    assert.is_function(mayScan)
    assert.is_false(mayScan())            -- outside a grant

    local seenInside
    GC.Sniper.scanner.OnSystemReady = function() seenInside = mayScan() end
    GC.Sniper._GrantWatchSlot()
    assert.is_true(seenInside)            -- inside its grant
    assert.is_false(mayScan())            -- and closed again straight after
  end)

  -- Confirmed live 2026-08-18: the watch loop's polls kept firing while the player tried to
  -- click Create Auction in Blizzard's own default sell panel, burning the same shared
  -- throttle budget and turning every click into "You're doing that too fast". PlayerIsBusy is
  -- the single predicate this gate reads now -- posting, buying a browse result, or reading
  -- their own search all vetoe the grant the same way.
  it("keeps the watch loop's grant closed while the player is busy, even mid-grant", function()
    local GC = load()
    local mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan
    GC.AuctionHouseTab = { PlayerIsBusy = function() return true end }

    local seenInside
    GC.Sniper.scanner.OnSystemReady = function() seenInside = mayScan() end
    GC.Sniper._GrantWatchSlot()
    assert.is_false(seenInside)          -- the grant window opens, but being busy still vetoes it

    GC.AuctionHouseTab.PlayerIsBusy = function() return false end
    GC.Sniper._GrantWatchSlot()
    assert.is_true(seenInside)           -- and resumes the moment the player is no longer busy
  end)

  it("does not wedge the gate open when the scanner throws", function()
    local GC = load()
    local mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan
    GC.Sniper.scanner.OnSystemReady = function() error("scanner blew up") end
    GC.Sniper._GrantWatchSlot()
    assert.is_false(mayScan())
  end)
end)
