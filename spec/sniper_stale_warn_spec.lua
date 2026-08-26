local helper = require("spec.spec_helper")

-- maybeWarnStale (UI/SniperFrame.lua) is the once-per-session chat warning printed on AH open
-- when the import is missing or badly stale. These tests pin the companion-first wording --
-- see refreshStaleText's sibling change in spec/sniper_stale_text_spec.lua for the header banner.
describe("Sniper stale-import chat warning (companion nudge)", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local origin, printed

  local function loadSniper()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000000 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }

    printed = nil
    origin = "none"
    local GC = {
      Theme = {
        ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { WATCH = { 1, 1, 1 } },
        color = { watch = { 0.35, 0.72, 0.9 }, gold = { 0.83, 0.64, 0.22 },
          fgDim = { 0.5, 0.5, 0.5 }, fg = { 0.92, 0.91, 0.89 }, green = { 0, 1, 0 }, red = { 1, 0, 0 } },
      },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end }
      end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      Data = { GetItemValue = function() return nil end, OriginState = function() return origin end },
      FullScan = {},
      db = { settings = { sniper = { watchPins = {} } } },
      Print = function(msg) printed = msg end,
    }
    helper.loadModule("Core/WatchSet.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer = nil, os.time, nil
  end)

  local function warn(GC)
    upvalue(GC.Sniper.OnAuctionHouseShow, "maybeWarnStale")()
  end

  it("points at the Companion first when nothing has ever been imported", function()
    local GC = loadSniper()
    origin = "none"
    warn(GC)
    assert.equal("you haven't imported realm prices yet -- install GoldCap Companion "
      .. "(/goldcap companion) or paste a string from goldcap.gg (/goldcap import).", printed)
  end)

  it("adds the companion alternative when a manual import has gone stale", function()
    local GC = loadSniper()
    origin = "manual"
    GC.db.imported = { ts = 1000000 - 25 * 3600 } -- 25h old: past the red threshold
    warn(GC)
    assert.matches("your import is 25 hours old", printed)
    assert.matches("Companion keeps this fresh: /goldcap companion%.$", printed)
  end)

  it("does not suggest the companion for stale app-synced data (it's already the source)", function()
    local GC = loadSniper()
    origin = "app"
    GC.db.imported = { ts = 1000000 - 25 * 3600, origin = "app" }
    warn(GC)
    assert.matches("your import is 25 hours old", printed)
    assert.not_matches("Companion", printed, nil, true)
  end)

  it("says nothing while the import is still fresh or yellow", function()
    local GC = loadSniper()
    origin = "manual"
    GC.db.imported = { ts = 1000000 - 7 * 3600 } -- 7h old: yellow, below the warn threshold
    warn(GC)
    assert.is_nil(printed)
  end)
end)
