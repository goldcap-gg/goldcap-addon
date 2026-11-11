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

    it("stays SCAN through Auto's own passes, and lights for a scan the player pressed", function()
      local GC = loadSniper()
      local refresh = upvalue(GC.Sniper.RepaintScanState, "refreshScanButton")
      local autoScan = upvalue(GC.Sniper.ScanActive, "autoScan")
      local b = fakeButton(function(t) return #t * 8 end)
      local state = "SCANNING"
      autoScan.State = function() return state end
      refresh({ fullScanBtn = b })
      assert.equal("SCAN", b.labels[#b.labels])
      assert.equal("ghost", b.variant)

      -- Between two passes the player presses SCAN, and the scan it starts runs.
      state = "IDLE"
      local createFrame = upvalue(GC.Sniper.OnAuctionHouseShow, "createFrame")
      local click = upvalue(createFrame, "onFullScanClick")
      for i = 1, math.huge do
        local name = debug.getupvalue(click, i)
        if not name then break end
        if name == "frame" then
          debug.setupvalue(click, i, { status = { SetText = function() end }, fullScanBtn = b })
        end
      end
      GC.Sniper.scanner = {}
      GC.ForeverScan.Request = function() foreverBusy = true; return "started" end
      click()
      refresh({ fullScanBtn = b })
      assert.equal("SCANNING…", b.labels[#b.labels])
      assert.equal("active", b.variant)

      -- It ends; Auto's next pass does not light the button again.
      foreverBusy = false
      refresh({ fullScanBtn = b })
      state = "SCANNING"
      refresh({ fullScanBtn = b })
      assert.equal("SCAN", b.labels[#b.labels])
      assert.equal("ghost", b.variant)
    end)

    -- Owner, WoW: Forever 2026-11-11: with Auto on, the full scan on opening the auction house ran
    -- its fifteen seconds with the chip on "AUTO · SCANNING", as it always is, and SCAN on idle:
    -- nothing on the board said a full scan was on. Auto's passes never make the full-scan machine
    -- busy, so the machine being busy is this button's to say, whatever the chip reads.
    it("lights for the full scan while the AUTO chip reads AUTO · SCANNING", function()
      local GC = loadSniper()
      local refresh = upvalue(GC.Sniper.RepaintScanState, "refreshScanButton")
      local autoScan = upvalue(GC.Sniper.ScanActive, "autoScan")
      local b = fakeButton(function(t) return #t * 8 end)
      autoScan.State = function() return "SCANNING" end
      foreverBusy = true
      refresh({ fullScanBtn = b })
      assert.equal("SCANNING…", b.labels[#b.labels])
      assert.equal("active", b.variant)
      foreverBusy = false
      refresh({ fullScanBtn = b })
      assert.equal("SCAN", b.labels[#b.labels])
      assert.equal("ghost", b.variant)
    end)

    -- Owner, WoW: Forever 11.10: Auto stood paused, the scan on opening the auction house read
    -- 75,230 lots, and SCAN read idle the whole time.
    it("lights for a scan while the AUTO chip names a pause or a hold, or reads plain AUTO", function()
      local GC = loadSniper()
      local refresh = upvalue(GC.Sniper.RepaintScanState, "refreshScanButton")
      local autoScan = upvalue(GC.Sniper.ScanActive, "autoScan")
      local b = fakeButton(function(t) return #t * 8 end)
      local state, reasons = "PAUSED", { tab = true }
      autoScan.State = function() return state end
      autoScan.PauseReasons = function() return reasons end
      foreverBusy = true
      refresh({ fullScanBtn = b })
      assert.equal("SCANNING…", b.labels[#b.labels])
      assert.equal("active", b.variant)
      reasons = { sell = true }
      refresh({ fullScanBtn = b })
      assert.equal("SCANNING…", b.labels[#b.labels])
      state, GC.Sniper._autoHeld = "WAITING", "busy"
      refresh({ fullScanBtn = b })
      assert.equal("SCANNING…", b.labels[#b.labels])
      -- The scan is over and Auto runs again: its own passes are the chip's to say.
      GC.Sniper._autoHeld, foreverBusy, state = nil, false, "SCANNING"
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

  -- Owner, WoW: Forever 2026-10-09: on a small auction house Auto's passes come and go every
  -- second, and AUTO and SCAN blinked with them. The chip says the mode; the status line beside it
  -- says each pass.
  describe("the AUTO chip", function()
    it("reads AUTO · SCANNING the whole time Auto runs, between passes too, on both games", function()
      local GC = loadSniper()
      local text = upvalue(upvalue(GC.Sniper.RepaintScanState, "refreshAutoButton"), "autoButtonText")
      for _, game in ipairs({ true, false }) do
        forever = game
        for _, busy in ipairs({ true, false }) do
          foreverBusy = busy
          for _, state in ipairs({ "IDLE", "SCANNING", "WAITING" }) do
            assert.equal("AUTO · SCANNING", text(state, {}), state)
          end
        end
      end
    end)

    it("still says a pause or a hold the player has to act on, and plain AUTO for the rest", function()
      local GC = loadSniper()
      local text = upvalue(upvalue(GC.Sniper.RepaintScanState, "refreshAutoButton"), "autoButtonText")
      foreverBusy = true
      assert.equal("AUTO · PAUSED: MAILBOX OPEN", text("PAUSED", { mail = true }))
      assert.equal("AUTO", text("PAUSED", { ah = true }))
      GC.Sniper._autoHeld = "busy"
      assert.equal("AUTO · WAITING FOR YOU", text("WAITING", {}))
      assert.equal("AUTO · WAITING FOR YOU", text("IDLE", {}))
      GC.Sniper._autoHeld = nil
    end)
  end)

  -- The light beside AUTO (owner, 2026-10-09: "a blinking green thing that says it is working"):
  -- it breathes for as long as Auto runs, the mode and not each pass, so it does not blink with
  -- every pass the way the chip used to.
  describe("the light beside AUTO", function()
    local function paint(GC, mutate)
      local refresh = upvalue(GC.Sniper.RepaintScanState, "refreshAutoButton")
      local autoScan = upvalue(refresh, "autoScan")
      if mutate then mutate(autoScan) end
      local f = { autoBtn = { SetVariant = function() end, SetLabel = function() end } }
      f.liveDot = { SetState = function(self, state) self.state, self.painted = state, true end }
      refresh(f)
      assert.is_true(f.liveDot.painted)
      return f.liveDot.state
    end

    it("breathes the whole time Auto runs, between passes too, on both games", function()
      for _, game in ipairs({ true, false }) do
        forever = game
        local GC = loadSniper()
        assert.equal("live", paint(GC, function(a) a:Input("toggleOn", 1) end)) -- IDLE
        assert.equal("live", paint(GC, function(a)
          a:Input("pause:mail", 1); a:Input("resume:mail", 1)
        end)) -- WAITING out its settle
      end
    end)

    it("holds amber while the chip names a pause or a hold", function()
      local GC = loadSniper()
      assert.equal("held", paint(GC, function(a) a:Input("toggleOn", 1); a:Input("pause:mail", 1) end))
      GC = loadSniper()
      GC.Sniper._autoHeld = "busy"
      assert.equal("held", paint(GC, function(a) a:Input("toggleOn", 1) end))
      GC.Sniper._autoHeld = nil
    end)

    it("is out while Auto is off, and while it is paused only for the auction house or its tab", function()
      local GC = loadSniper()
      assert.is_nil(paint(GC))
      assert.is_nil(paint(GC, function(a) a:Input("toggleOn", 1); a:Input("ahClosed", 1) end))
    end)

    it("breathes for a scan the player started with Auto off", function()
      local GC = loadSniper()
      GC.Sniper._bookPass:Start("classes")
      assert.equal("live", paint(GC))
    end)

    it("is out on every tab but Deals", function()
      local GC = loadSniper()
      local refresh = upvalue(GC.Sniper.RepaintScanState, "refreshAutoButton")
      for i = 1, math.huge do
        local name = debug.getupvalue(refresh, i)
        assert.is_not_nil(name, "missing upvalue view")
        if name == "view" then debug.setupvalue(refresh, i, "sell"); break end
      end
      assert.is_nil(paint(GC, function(a) a:Input("toggleOn", 1) end))
    end)
  end)

  describe("the full scan on the status line (Forever)", function()
    local function withStatus(GC)
      local status = { writes = {} }
      function status:SetText(text) self.text = text; self.writes[#self.writes + 1] = text end
      function status:GetText() return self.text end
      local setStatus = upvalue(GC.Sniper.SetScanStatus, "setStatus")
      for i = 1, math.huge do
        local name = debug.getupvalue(setStatus, i)
        if not name then break end
        if name == "frame" then debug.setupvalue(setStatus, i, { status = status }) end
      end
      return status
    end

    it("counts the seconds while the list is waited for and while the scan browses", function()
      local GC = loadSniper()
      GC.Util = { FormatElapsedWords = function(n) return n .. "s" end }
      local status = withStatus(GC)
      local run = { "waiting", 1000 }
      GC.ForeverScan.Running = function() return run[1], run[2] end
      _G.time = function() return 1007 end
      GC.Sniper._ScanLine()
      assert.equal("Scanning the auction house… 7s", status.text)
      run = { "browsing", 1000 }
      _G.time = function() return 1012 end
      GC.Sniper._ScanLine()
      assert.equal("Scanning the auction house… 12s", status.text)
      _G.time = os.time
    end)

    it("leaves the line to the read's own progress, and alone when no scan runs", function()
      local GC = loadSniper()
      GC.Util = { FormatElapsedWords = function(n) return n .. "s" end }
      local status = withStatus(GC)
      local run = { "reading", 1000 }
      GC.ForeverScan.Running = function() return run[1], run[2] end
      GC.Sniper._ScanLine()
      run = {}
      GC.Sniper._ScanLine()
      assert.same({}, status.writes)
    end)

    it("gives way to a line the player's own action holds", function()
      local GC = loadSniper()
      GC.Util = { FormatElapsedWords = function(n) return n .. "s" end }
      local status = withStatus(GC)
      GC.ForeverScan.Running = function() return "waiting", 1000 end
      GC.Sniper.SetScanStatus("watching item 7", 4)
      GC.Sniper._ScanLine()
      assert.equal("watching item 7", status.text)
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
