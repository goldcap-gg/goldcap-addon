local helper = require("spec.spec_helper")

-- refreshStaleText (UI/SniperFrame.lua) is the Sniper header's "where did these prices come
-- from" banner. It used to lead with the manual-paste command no matter what; these tests pin
-- the companion-first wording per origin state (GC.Data.OriginState()) and the new click target.
describe("Sniper stale-text banner (companion nudge)", function()
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

  local function fontString()
    local w = { shown = false, colors = {} }
    function w:SetText(text) self.text = text end
    function w:SetTextColor(r, g, b) self.colors = { r, g, b } end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
  end

  local origin, staleFrame, companionShown

  local function loadSniper()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000000 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.CreateFrame = function(kind, name, parent)
      return {
        kind = kind, name = name, parent = parent, mouseEnabled = false, scripts = {},
        EnableMouse = function(self, v) self.mouseEnabled = v end,
        SetScript = function(self, ev, fn) self.scripts[ev] = fn end,
        SetAllPoints = function(self, rel) self.allPointsTarget = rel end,
      }
    end

    companionShown = false
    origin = "none"
    local db = { settings = { sniper = { watchPins = {} } } }
    local GC = {
      Theme = {
        ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { WATCH = { 1, 1, 1 }, SUSPECT = { 1, 0.6, 0 } },
        color = { watch = { 0.35, 0.72, 0.9 }, gold = { 0.83, 0.64, 0.22 },
          fgDim = { 0.5, 0.5, 0.5 }, fg = { 0.92, 0.91, 0.89 }, green = { 0, 1, 0 }, red = { 1, 0, 0 } },
      },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end }
      end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      -- OriginState is faked directly (not derived from db) so each test can drive it
      -- independently of the age math importAgeSeconds() does from db.imported.ts.
      Data = { GetItemValue = function() return nil end, OriginState = function() return origin end },
      FullScan = {},
      CompanionUI = { Show = function() companionShown = true end },
      db = db,
    }
    helper.loadModule("Core/WatchSet.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    staleFrame = { staleText = fontString() }
    set(GC.Sniper.OnAuctionHouseShow, "frame", staleFrame)

    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer, _G.CreateFrame = nil, os.time, nil, nil
  end)

  local function refresh(GC)
    upvalue(GC.Sniper.OnAuctionHouseShow, "refreshStaleText")()
  end

  it("says no prices yet and is clickable to open the Companion dialog", function()
    local GC = loadSniper()
    origin = "none"
    refresh(GC)
    assert.equal("no prices yet -- install GoldCap Companion (/goldcap companion) or /goldcap import",
      staleFrame.staleText.text)
    assert.same({ 1, 0, 0 }, staleFrame.staleText.colors)
    assert.is_true(staleFrame.staleText.shown)
    assert.is_true(staleFrame.staleHit.mouseEnabled)
    staleFrame.staleHit.scripts.OnMouseUp()
    assert.is_true(companionShown)
  end)

  it("shows a dim companion nudge for a fresh manual import instead of hiding", function()
    local GC = loadSniper()
    origin = "manual"
    GC.db.imported = { ts = 1000000 } -- age 0: fresh
    refresh(GC)
    assert.equal("manual import -- Companion keeps this fresh: /goldcap companion", staleFrame.staleText.text)
    assert.is_true(staleFrame.staleText.shown)
    assert.is_true(staleFrame.staleHit.mouseEnabled)
  end)

  it("keeps the yellow manual wording as-is", function()
    local GC = loadSniper()
    origin = "manual"
    GC.db.imported = { ts = 1000000 - 7 * 3600 } -- 7h old: yellow band
    refresh(GC)
    assert.equal("import 7h old", staleFrame.staleText.text)
    assert.is_true(staleFrame.staleHit.mouseEnabled)
  end)

  it("adds the companion alternative to the red manual wording", function()
    local GC = loadSniper()
    origin = "manual"
    GC.db.imported = { ts = 1000000 - 25 * 3600 } -- 25h old: red band
    refresh(GC)
    assert.equal("import stale -- /goldcap import or /goldcap companion", staleFrame.staleText.text)
    assert.is_true(staleFrame.staleHit.mouseEnabled)
  end)

  it("leaves red app-synced wording unchanged and not clickable", function()
    local GC = loadSniper()
    origin = "app"
    GC.db.imported = { ts = 1000000 - 25 * 3600, origin = "app" }
    refresh(GC)
    assert.equal("auto-synced data stale -- /goldcap import", staleFrame.staleText.text)
    assert.is_false(staleFrame.staleHit.mouseEnabled)
  end)

  it("still hides fresh app-synced data, not clickable", function()
    local GC = loadSniper()
    origin = "app"
    GC.db.imported = { ts = 1000000, origin = "app" }
    refresh(GC)
    assert.is_false(staleFrame.staleText.shown)
    assert.is_false(staleFrame.staleHit.mouseEnabled)
  end)
end)
