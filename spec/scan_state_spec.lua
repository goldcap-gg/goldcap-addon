local helper = require("spec.spec_helper")

-- Owner, WoW: Forever beta 2026-09-30: the SCAN button read idle while a scan ran, a click on it
-- then started a second scan and a second summary block, its longer label was cut off, and the
-- chat repeated the same how-to lines after every scan. One answer now -- GC.Sniper.ScanActive --
-- drives the button, the AUTO chip and the click.
describe("one scan state for the toolbar", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local forever, foreverBusy

  local function loadSniper()
    _G.GetTime = function() return 100 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, Scale = function() return 1 end,
        pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 }, fgDim = { 0.55, 0.54, 0.52 },
          red = { 0.9, 0.28, 0.3 }, green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      Data = { GetItemValue = function() return nil end },
      Game = { IsForever = function() return forever end, Passport = function() return {} end },
      ForeverScan = { IsBusy = function() return foreverBusy end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    return GC
  end

  before_each(function() forever, foreverBusy = true, false end)
  after_each(function()
    _G.GetTime, _G.C_Timer, _G.Item = nil, nil, nil
  end)

  describe("GC.Sniper.ScanActive", function()
    it("is false when nothing runs", function()
      local GC = loadSniper()
      assert.is_false(GC.Sniper.ScanActive())
    end)

    it("is true while the book pass pages, on either game", function()
      local GC = loadSniper()
      GC.Sniper._bookPass.IsPaging = function() return true end
      assert.is_true(GC.Sniper.ScanActive())
      forever = false
      assert.is_true(GC.Sniper.ScanActive())
    end)

    it("follows the Forever scanner, including the held summary, but only in Forever", function()
      local GC = loadSniper()
      foreverBusy = true
      assert.is_true(GC.Sniper.ScanActive())
      forever = false
      assert.is_false(GC.Sniper.ScanActive())
    end)

    it("counts a pass that is armed but not sent yet, and Auto's own SCANNING, in Forever", function()
      local GC = loadSniper()
      GC.Sniper._bookPass.PendingStart = function() return true end
      assert.is_true(GC.Sniper.ScanActive())
      GC.Sniper._bookPass.PendingStart = function() return false end
      local autoScan = upvalue(GC.Sniper.ScanActive, "autoScan")
      autoScan.State = function() return "SCANNING" end
      assert.is_true(GC.Sniper.ScanActive())
      forever = false
      assert.is_false(GC.Sniper.ScanActive())
    end)
  end)

  describe("the SCAN button", function()
    local function fakeButton(widthOf)
      local b = { labels = {}, widths = {} }
      b.text = {
        current = "",
        SetText = function(self, t) self.current = t end,
        GetUnboundedStringWidth = function(self) return widthOf(self.current) end,
      }
      b.SetLabel = function(self, t) self.labels[#self.labels + 1] = t; self.text.current = t end
      b.SetVariant = function(self, v) self.variant = v end
      b.SetWidth = function(self, w) self.widths[#self.widths + 1] = w end
      return b
    end

    it("says the scanner's state: SCANNING while one runs, SCAN when none does", function()
      local GC = loadSniper()
      local refresh = upvalue(GC.Sniper.RepaintScanState, "refreshScanButton")
      local b = fakeButton(function(t) return #t * 8 end)
      foreverBusy = true
      refresh({ fullScanBtn = b })
      assert.equal("SCANNING…", b.labels[#b.labels])
      assert.equal("active", b.variant)
      foreverBusy = false
      refresh({ fullScanBtn = b })
      assert.equal("SCAN", b.labels[#b.labels])
      assert.equal("ghost", b.variant)
    end)

    it("is sized to the longer label, never under the old 64px, and measured once", function()
      local GC = loadSniper()
      local refresh = upvalue(GC.Sniper.RepaintScanState, "refreshScanButton")
      local b = fakeButton(function(t) return select(2, t:gsub("[^\128-\191]", "")) * 8 end)
      refresh({ fullScanBtn = b })
      refresh({ fullScanBtn = b })
      assert.equal(1, #b.widths)
      -- "SCANNING…" is 9 characters here: 72 + 2 * pad.m
      assert.equal(72 + 16, b.widths[1])
      local short = fakeButton(function() return 10 end)
      local GC2 = loadSniper()
      upvalue(GC2.Sniper.RepaintScanState, "refreshScanButton")({ fullScanBtn = short })
      assert.equal(64, short.widths[1])
    end)

    it("fits its longest label in every language", function()
      -- ~8px a character at the default scale; the button is sized to the label, so what this
      -- pins is that no language's pair is long enough to crowd the toolbar row (AUTO, status,
      -- SCAN, HIDDEN share 600px): 14 characters is the ceiling.
      for _, code in ipairs(helper.localeCodes()) do
        local GC = helper.loadModule("Locale/Core.lua")
        helper.loadModule("Locale/" .. code .. ".lua", GC)
        local t = GC.Locales[code]
        for _, key in ipairs({ "SCAN", "SCANNING…" }) do
          local _, n = (t[key] or key):gsub("[^\128-\191]", "")
          assert.is_true(n <= 14, code .. " " .. key .. " is " .. n .. " characters")
        end
      end
    end)
  end)

  describe("the AUTO chip", function()
    it("follows the scanner in Forever, yields to a pause, and is untouched on retail", function()
      local GC = loadSniper()
      local text = upvalue(upvalue(GC.Sniper.RepaintScanState, "refreshAutoButton"), "autoButtonText")
      foreverBusy = true
      assert.equal("AUTO · SCANNING", text("IDLE", {}))
      assert.equal("AUTO · PAUSED: MAILBOX OPEN", text("PAUSED", { mail = true }))
      foreverBusy = false
      assert.equal("AUTO", text("IDLE", {}))
      foreverBusy = true
      forever = false
      assert.equal("AUTO", text("IDLE", {}))
      assert.equal("AUTO · SCANNING", text("SCANNING", {}))
    end)
  end)

  it("a click on SCAN while a scan runs starts nothing (Forever)", function()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua"))
    local src = f:read("*a")
    f:close()
    local click = src:sub((src:find("local function onFullScanClick()", 1, true)))
    local guard = assert(click:find("GC.Sniper.ScanActive() or GC.ForeverScan.Request(\"button\")", 1, true))
    -- Short-circuits: Request is only reached when nothing runs.
    assert.is_true(guard < click:find("startFullScan()", 1, true))
  end)

  it("widens the verdict column only in Forever", function()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua"))
    local src = f:read("*a")
    f:close()
    assert.truthy(src:find('col.w = isForever() and WIN.FOREVER_TIER_W or WIN.TIER_W', 1, true))
    assert.equal(80, tonumber(src:match("WIN%.TIER_W = (%d+)")))
  end)
end)
