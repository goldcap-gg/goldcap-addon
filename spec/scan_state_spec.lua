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

    -- Owner, WoW: Forever 2026-11-23: "how long is left to wait, in the tooltip and by the icon".
    it("carries the minutes to the next full list on the spyglass, none while it scans or once due", function()
      local GC = loadSniper()
      local refresh = upvalue(GC.Sniper.RepaintScanState, "refreshScanButton")
      local b = fakeButton(function(t) return #t * 8 end)
      b.SetCount = function(self, n) self.count = n end
      local wait = 250
      GC.ForeverScan.DueIn = function() return wait end
      refresh({ fullScanBtn = b })
      assert.equal(5, b.count)
      wait = 0
      refresh({ fullScanBtn = b })
      assert.is_nil(b.count)
      wait, foreverBusy = 250, true
      refresh({ fullScanBtn = b })
      assert.is_nil(b.count)
      foreverBusy, forever = false, false
      refresh({ fullScanBtn = b })
      assert.is_nil(b.count)
    end)

    -- Owner, 2026-11-23: the spyglass stopped once the list's first 1024 rows were saved, and the
    -- rest of it came in unseen; a browse in the throttle's place turned it like a full list.
    it("turns for the full list from its request to its last stage, and for nothing else", function()
      local GC = loadSniper()
      local refresh = upvalue(GC.Sniper.RepaintScanState, "refreshScanButton")
      local b = fakeButton(function(t) return #t * 8 end)
      local full = true
      GC.ForeverScan.FullListOn = function() return full end
      refresh({ fullScanBtn = b })                 -- between the stages: the scanner idle
      assert.equal("SCANNING…", b.labels[#b.labels])
      assert.equal("active", b.variant)
      full, foreverBusy = false, true              -- a browse in the throttle's place
      refresh({ fullScanBtn = b })
      assert.equal("SCAN", b.labels[#b.labels])
      assert.equal("ghost", b.variant)
    end)

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
      assert.equal("Scanning the auction house… 7s · do not close the auction house", status.text)
      run = { "browsing", 1000 }
      _G.time = function() return 1012 end
      GC.Sniper._ScanLine()
      assert.equal("Scanning the auction house… 12s · do not close the auction house", status.text)
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

  -- A player, 2026-11-17 (0.29.0, and 0.28.1 the same): a search of their own on the auction
  -- house's Buy list, then SCAN. On retail that press hands the list back to GoldCap; on Forever it
  -- did not, so the pass the scan armed never started. The scan stopped waiting for it after three
  -- minutes, the pass stayed armed, and SCAN read SCANNING with nothing running and no count beside
  -- it, answering every press with "full scan already in progress" until the auction house closed.
  describe("SCAN and the player's own use of the auction house (Forever)", function()
    it("a press takes the Buy list back from the player's own search, then asks for the scan", function()
      local GC = loadSniper()
      local order = {}
      GC.AuctionHouseTab = { ReleaseBrowseList = function() order[#order + 1] = "release" end }
      GC.ForeverScan.Request = function(reason) order[#order + 1] = "request " .. reason; return "started" end
      assert.is_false(GC.Sniper._ForeverScanPress())
      assert.same({ "release", "request button" }, order)
    end)

    it("a press while the market scan runs starts nothing, and still takes the list back", function()
      local GC = loadSniper()
      local order = {}
      GC.AuctionHouseTab = { ReleaseBrowseList = function() order[#order + 1] = "release" end }
      GC.ForeverScan.Request = function() order[#order + 1] = "request"; return "started" end
      GC.ForeverScan.IsBusy = function() return true end
      assert.is_true(GC.Sniper._ForeverScanPress())
      assert.same({ "release" }, order)
    end)

    -- Owner, 2026-11-23: Auto on, SCAN pressed for 15 minutes, "full scan already in progress"
    -- every time and no scan: Auto's own pass counted as the scan.
    it("a press while only a browse pass pages (Auto's) asks for the scan", function()
      local GC = loadSniper()
      local order = {}
      GC.ForeverScan.Request = function(reason) order[#order + 1] = "request " .. reason; return "started" end
      GC.ForeverScan.IsBusy = function() return false end
      GC.Sniper._bookPass:Start("wide")
      assert.is_false(GC.Sniper._ForeverScanPress())
      assert.same({ "request button" }, order)
    end)

    it("a press the scanner refuses as busy says a scan runs", function()
      local GC = loadSniper()
      GC.ForeverScan.Request = function() return "busy" end
      assert.is_true(GC.Sniper._ForeverScanPress())
    end)

    it("the click goes through that press, ahead of retail's own pass", function()
      local f = assert(io.open("GoldCap/UI/SniperFrame.lua"))
      local src = f:read("*a")
      f:close()
      local click = src:sub((src:find("local function onFullScanClick()", 1, true)))
      local press = assert(click:find("GC.Sniper._ForeverScanPress()", 1, true))
      assert.is_true(press < click:find("startFullScan()", 1, true))
    end)

    it("ends a pass that is out when the scan stops waiting for it, and tells the scan", function()
      local GC = loadSniper()
      local told = {}
      GC.ForeverScan.OnBrowsePassAbandoned = function(book) told[#told + 1] = type(book) end
      GC.Sniper._bookPass:Start("wide")
      assert.is_true(GC.Sniper.ScanActive())
      GC.Sniper.StopBrowsePass()
      assert.is_false(GC.Sniper.ScanActive())
      assert.same({ "table" }, told)
      GC.Sniper.StopBrowsePass()                 -- nothing is out: nothing to end
      assert.same({ "table" }, told)
    end)

    it("knows when the player's own use of the auction house holds a pass back", function()
      local GC = loadSniper()
      assert.is_false(GC.Sniper.BrowseHeld())    -- no tab to ask: fails open
      local busy, owned = false, false
      GC.AuctionHouseTab = { PlayerIsBusy = function() return busy end,
        PlayerOwnsBrowseList = function() return owned end }
      assert.is_false(GC.Sniper.BrowseHeld())
      busy = true
      assert.is_true(GC.Sniper.BrowseHeld())
      busy, owned = false, true
      assert.is_true(GC.Sniper.BrowseHeld())
    end)

    it("says what a held pass waits for on the status line, in place of the count", function()
      local GC = loadSniper()
      GC.Util = { FormatElapsedWords = function(n) return n .. "s" end }
      _G.time = function() return 1012 end
      GC.ForeverScan.Running = function() return "browsing", 1000 end
      local buying, aside = false, false
      GC.AuctionHouseTab = { PlayerIsBuying = function() return buying end,
        PlayerIsAside = function() return aside end }
      GC.Sniper._bookPass:Start("wide")          -- armed, not sent
      local count = "Scanning the auction house… 12s · do not close the auction house"
      local waits = "Scan starts when you leave that tab: click Buy or GoldCap"
      assert.equal(count, GC.Sniper._ScanLineText())
      buying = true                              -- the player's own buy page is up
      assert.equal(waits, GC.Sniper._ScanLineText())
      buying, aside = false, true                -- Sell, Auctions or another addon's tab
      assert.equal(waits, GC.Sniper._ScanLineText())
      GC.Sniper._bookPass.PendingStart = function() return false end -- the pass went out
      assert.equal(count, GC.Sniper._ScanLineText())
      GC.ForeverScan.Running = function() return "waiting", 1000 end
      assert.equal(count, GC.Sniper._ScanLineText())
      GC.ForeverScan.Running = function() return "reading", 1000 end
      assert.is_nil(GC.Sniper._ScanLineText())
      _G.time = os.time
    end)
  end)

  it("widens the verdict column only in Forever", function()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua"))
    local src = f:read("*a")
    f:close()
    assert.truthy(src:find('col.w = isForever() and WIN.FOREVER_TIER_W or WIN.TIER_W', 1, true))
    assert.equal(80, tonumber(src:match("WIN%.TIER_W = (%d+)")))
  end)
end)
