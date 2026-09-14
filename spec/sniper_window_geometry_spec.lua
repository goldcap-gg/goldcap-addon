local helper = require("spec.spec_helper")

-- The window's saved size has always been clamped (WIN.RESIZE_MIN/MAX); its saved POSITION was
-- only type-checked. So a position saved on one screen was replayed verbatim onto another: a
-- resolution change, a UI-scale change, a second monitor unplugged, or a hand-edited
-- SavedVariables, and the window opens somewhere nobody can see -- which is also somewhere
-- nobody can drag it back from, because the title bar it is dragged by went off-screen with it.
--
-- Reached the same debug.getupvalue way spec/toolbar_chrome_spec.lua reaches setView: every
-- closure in the SniperFrame.lua chunk shares one cell per module-local, and createFrame is a
-- direct upvalue of OnAuctionHouseShow.
describe("Saved window position", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function clampOf()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.GetCoinTextureString = function(copper) return tostring(copper) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}

    local GC = {
      Theme = {
        ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { WATCH = { 1, 1, 1 } },
        color = { watch = { 0.35, 0.72, 0.90 }, gold = { 0.83, 0.64, 0.22 }, fgDim = { 0.5, 0.5, 0.5 },
          fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 }, green = { 0, 1, 0 }, red = { 1, 0, 0 } },
      },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end }
      end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      Data = { GetItemValue = function() return nil end },
      FullScan = {},
      Sell = { Show = function() end, Hide = function() end },
      db = { settings = { sniper = {} } },
    }
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/BoardRows.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local createFrame = upvalue(GC.Sniper.OnAuctionHouseShow, "createFrame")
    return upvalue(createFrame, "clampWindowOffset")
  end

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer, _G.Item = nil, os.time, nil, nil
    _G.GetCoinTextureString, _G.ITEM_QUALITY_COLORS = nil, nil
  end)

  -- Offsets are measured from UIParent, so half of the matching screen dimension keeps the
  -- anchor inside the middle half of the screen -- some of the window, title bar included,
  -- is always on screen and always reachable.
  it("keeps an offset saved on a bigger screen inside this one", function()
    local clamp = clampOf()
    assert.equal(960, clamp(4000, 1920))
    assert.equal(-540, clamp(-4000, 1080))
  end)

  it("leaves a position that already fits exactly where the player put it", function()
    local clamp = clampOf()
    assert.equal(120, clamp(120, 1920))
    assert.equal(-300, clamp(-300, 1080))
    assert.equal(0, clamp(0, 1920))
  end)

  -- The screen size comes from UIParent, which can answer with nothing at all this early in a
  -- login. A clamp that cannot be computed must hand the saved value straight through rather
  -- than invent a position: the SetPoint it feeds is the one that has to keep working.
  it("hands the value through when there is no screen size to measure against", function()
    local clamp = clampOf()
    assert.equal(4000, clamp(4000, nil))
    assert.equal(4000, clamp(4000, 0))
    assert.equal("junk", clamp("junk", 1920))
  end)
end)
