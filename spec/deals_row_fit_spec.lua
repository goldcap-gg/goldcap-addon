local helper = require("spec.spec_helper")

-- The Deals list cut a long item cell with "…" (a narrow window, a long language). The cell wraps
-- now and its row grows to hold it, the way the Sell tab's cards do; rows stack one under another,
-- and none moves while the cursor rests on one or a purchase holds one.
describe("Deals rows as tall as their words", function()
  local GC

  local function loadSniper()
    _G.GetTime = function() return 100 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    GC = {
      Theme = { ROW_H = 32, RAIL_W = 76, Scale = function() return 1 end,
        pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 1, 1, 1 }, fgMuted = { 1, 1, 1 }, fgDim = { 1, 1, 1 },
          red = { 1, 0, 0 }, green = { 0, 1, 0 }, gold = { 1, 1, 0 } } },
      Data = { GetItemValue = function() return nil end },
      Game = { IsForever = function() return false end, Passport = function() return {} end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
  end

  -- A row whose item cell measures `lines` lines of 15px at its width.
  local function row(lines, shown)
    local r = { shown = shown ~= false, height = 32, sets = 0 }
    r.nameText = {
      words = ("word "):rep(lines),
      GetText = function(self) return self.words end,
      SetText = function(self, t) self.words = t end,
      GetWidth = function() return 180 end,
      GetStringHeight = function() return 15 * lines end,
    }
    function r:IsShown() return self.shown end
    function r:GetHeight() return self.height end
    function r:SetHeight(h) self.height = h; self.sets = self.sets + 1 end
    return r
  end

  local function child()
    local c = {}
    function c:SetHeight(h) self.height = h end
    return c
  end

  before_each(loadSniper)
  after_each(function() _G.GetTime, _G.C_Timer, _G.Item = nil, nil, nil end)

  it("keeps a one-line row at the list's own height and grows a wrapped one to hold it", function()
    local rows, content = { row(1), row(3), row(1) }, child()
    GC.Sniper._FitRowHeights(rows, content, false)
    assert.equal(32, rows[1].height)
    assert.is_true(rows[2].height >= 45 + 2 * 4)
    assert.equal(32, rows[3].height)
    assert.equal(32 + rows[2].height + 32, content.height)
  end)

  it("makes the list as tall as its rows down to the last one shown", function()
    local rows, content = { row(1), row(2), row(1, false), row(1, false) }, child()
    GC.Sniper._FitRowHeights(rows, content, false)
    assert.equal(32 + rows[2].height, content.height)
    rows = { row(1, false) }
    GC.Sniper._FitRowHeights(rows, content, false)
    assert.equal(32, content.height)
  end)

  it("measures a row again only when its words or its width changed", function()
    local rows, content = { row(2) }, child()
    local measured = 0
    local height = rows[1].nameText.GetStringHeight
    rows[1].nameText.GetStringHeight = function(...) measured = measured + 1; return height(...) end
    GC.Sniper._FitRowHeights(rows, content, false)
    GC.Sniper._FitRowHeights(rows, content, false)
    assert.equal(1, measured)
    rows[1].nameText.words = "another name altogether"
    GC.Sniper._FitRowHeights(rows, content, false)
    assert.equal(2, measured)
  end)

  it("moves no row while the cursor rests on one or a purchase holds one", function()
    local rows, content = { row(1), row(3) }, child()
    GC.Sniper._FitRowHeights(rows, content, true)
    assert.equal(0, rows[1].sets)
    assert.equal(0, rows[2].sets)
    assert.equal(64, content.height) -- the list still covers the rows as they stand
  end)
end)
