local helper = require("spec.spec_helper")

-- The right-click pin looked dead in game three separate ways: the status announcement was
-- overwritten within a frame by scan spam, the hovered row (the one the click happened on, by
-- definition) was exempt from repaint, and a single-phase mouse handler was a bet on which
-- phase a trackpad tap actually delivers. These tests pin down the fixes: the dual-phase
-- latch, the status hold, and the empty-state panel that explains a board with nothing on it.
describe("Sniper pin feedback and empty state", function()
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

  local clock

  local function fontString()
    local w = { shown = false }
    function w:SetText(text) self.text = text end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
  end

  local function loadSniper(pins)
    clock = 100
    _G.GetTime = function() return clock end
    _G.time = function() return 1000 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.GetCoinTextureString = function(copper) return tostring(copper) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}

    -- Declared before GC so OriginState's closure (below) captures THIS table, not whatever
    -- name `GC` resolves to at the point the anonymous function is defined -- `local GC = {...}`
    -- only brings the new local into scope after the whole initializer has run.
    local db = { settings = { sniper = { watchPins = pins or {} } } }
    local GC = {
      Theme = {
        ROW_H = 20,
        RAIL_W = 76,
        pad = { m = 8, s = 4, xs = 2 },
        tier = { WATCH = { 1, 1, 1 } },
        color = { watch = { 0.35, 0.72, 0.90 }, gold = { 0.83, 0.64, 0.22 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 },
          fg = { 0.92, 0.91, 0.89 }, green = { 0, 1, 0 }, red = { 1, 0, 0 } },
      },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end }
      end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      -- OriginState mirrors Core/Data.lua's real rule (ts nil -> "none", origin "app" -> "app",
      -- else "manual") so the "names the hidden and refused counts"/"suggests scanning" tests
      -- below -- which only ever set db.imported.ts, no origin -- keep landing past the "none"
      -- branch the empty-state companion nudge now gates on.
      Data = { GetItemValue = function() return nil end, OriginState = function()
        local imp = db.imported
        if not imp or not imp.ts then return "none" end
        if imp.origin == "app" then return "app" end
        return "manual"
      end },
      FullScan = {},
      db = db,
    }
    helper.loadModule("Core/WatchSet.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/BoardRows.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    -- A status line and empty-state label the module-level `frame` cell points at, plus the
    -- row-pool stubs that let refreshRows run headless (same seam auto_verify_spec uses).
    local status, emptyText = fontString(), fontString()
    local refreshRows = upvalue(GC.Sniper.OnAuctionHouseShow, "refreshRows")
    set(GC.Sniper.OnAuctionHouseShow, "frame",
      { IsShown = function() return true end, Hide = function() end, status = status, emptyText = emptyText })
    set(refreshRows, "content", { SetHeight = function() end })
    set(refreshRows, "createRow", function()
      local row = { shownState = false }
      for _, key in ipairs({ "buy", "tierChip", "icon", "nameText", "discountText",
        "unitText", "priceText", "profitText", "trendText", "highlight", "rail", "pinBg" }) do
        row[key] = setmetatable({}, { __index = function() return function() end end })
      end
      function row:Show() self.shownState = true end
      function row:Hide() self.shownState = false end
      function row:IsShown() return self.shownState end
      function row:SetAlpha() end
      return row
    end)
    return GC, status, emptyText
  end

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer, _G.Item = nil, os.time, nil, nil
    _G.GetCoinTextureString, _G.ITEM_QUALITY_COLORS = nil, nil
  end)

  local function pinned(GC)
    return GC.db.settings.sniper.watchPins
  end

  describe("dual-phase right-click latch", function()
    it("toggles once for a press that delivers both down and up", function()
      local GC = loadSniper()
      local row = { deal = { itemID = 7 } }
      GC.Sniper._RowPinEvent(row, "down", "RightButton")
      GC.Sniper._RowPinEvent(row, "up", "RightButton")
      assert.same({ 7 }, pinned(GC))
    end)

    it("toggles once for a press that delivers only the up phase", function()
      local GC = loadSniper()
      local row = { deal = { itemID = 7 } }
      GC.Sniper._RowPinEvent(row, "up", "RightButton")
      assert.same({ 7 }, pinned(GC))
    end)

    it("toggles once for a press that delivers only the down phase, and stays consistent on the next press", function()
      local GC = loadSniper()
      local row = { deal = { itemID = 7 } }
      GC.Sniper._RowPinEvent(row, "down", "RightButton")
      assert.same({ 7 }, pinned(GC))
      -- Next full press unpins -- the latch from the up-less press must not eat this one's toggle.
      GC.Sniper._RowPinEvent(row, "down", "RightButton")
      GC.Sniper._RowPinEvent(row, "up", "RightButton")
      assert.same({}, pinned(GC))
    end)

    it("never toggles the second row when a press is dragged from one row to another", function()
      local GC = loadSniper()
      GC.Sniper._RowPinEvent({ deal = { itemID = 7 } }, "down", "RightButton")
      GC.Sniper._RowPinEvent({ deal = { itemID = 9 } }, "up", "RightButton")
      assert.same({ 7 }, pinned(GC))
    end)

    it("ignores every other button and rows with no deal", function()
      local GC = loadSniper()
      GC.Sniper._RowPinEvent({ deal = { itemID = 7 } }, "down", "LeftButton")
      GC.Sniper._RowPinEvent({}, "down", "RightButton")
      assert.same({}, pinned(GC))
    end)
  end)

  describe("status hold", function()
    it("keeps the pin announcement up against periodic status writes until the hold expires", function()
      local GC, status = loadSniper()
      GC.Sniper._TogglePin(7)
      assert.matches("watching item 7", status.text)

      -- The scanner's per-send status line -- the exact writer that used to erase the
      -- announcement within a frame.
      local driver = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
      clock = 101
      driver.onStatus("scanning 1/10")
      assert.matches("watching item 7", status.text)

      clock = 105 -- past the 4s hold
      driver.onStatus("scanning 2/10")
      assert.equals("scanning 2/10", status.text)
    end)

    it("lets a newer held announcement replace an older one immediately", function()
      local GC, status = loadSniper()
      GC.Sniper._TogglePin(7)
      clock = 101
      GC.Sniper._TogglePin(7) -- unpin: a fresh player action always speaks
      assert.matches("stopped watching item 7", status.text)
    end)
  end)

  describe("empty-state panel", function()
    it("stays hidden while rows are on the board", function()
      local GC, _, emptyText = loadSniper()
      emptyText.shown = true
      GC.Sniper._UpdateEmptyState(3)
      assert.is_false(emptyText.shown)
    end)

    it("points at the Companion first, with manual import as the alternative", function()
      local GC, _, emptyText = loadSniper()
      GC.Sniper._UpdateEmptyState(0)
      assert.is_true(emptyText.shown)
      assert.matches("no realm prices yet", emptyText.text)
      assert.matches("goldcap companion", emptyText.text)
      assert.matches("goldcap import", emptyText.text)
    end)

    it("names the hidden and refused counts when the filters emptied the board", function()
      local GC, _, emptyText = loadSniper()
      GC.db.imported = { ts = 990 }
      local ids = { 1 }
      GC.Data.FactItemIds = function() return ids end
      GC.db.settings.sniper.minimumProfitCopper = 50000
      GC.db.settings.sniper.minimumRoi = 0.10
      GC.Data.GetItemValue = function() return { mv = 250000, stressUnit = 200000 } end
      GC.Sniper._screenedCount = 5
      set(GC.Sniper._UpdateEmptyState, "refusedCount", 3)
      GC.Sniper._UpdateEmptyState(0)
      assert.is_true(emptyText.shown)
      assert.matches("5 filtered out", emptyText.text)
      assert.matches("3 refused by live checks", emptyText.text)
      assert.matches('"HIDDEN 3"', emptyText.text)
    end)

    it("suggests scanning when there is simply nothing yet", function()
      local GC, _, emptyText = loadSniper()
      GC.db.imported = { ts = 990 }
      local ids = { 1 }
      GC.Data.FactItemIds = function() return ids end
      GC.db.settings.sniper.minimumProfitCopper = 50000
      GC.db.settings.sniper.minimumRoi = 0.10
      GC.Data.GetItemValue = function() return { mv = 250000, stressUnit = 200000 } end
      GC.Sniper._screenedCount = 0
      GC.Sniper._UpdateEmptyState(0)
      assert.is_true(emptyText.shown)
      assert.matches("Press Scan", emptyText.text)
    end)

    it("names the missing import when an import exists but nothing in it can ever arm", function()
      local GC, _, emptyText = loadSniper()
      GC.db.imported = { ts = 1000 } -- present, but no usable V fact
      local ids = { 1 }
      GC.Data.FactItemIds = function() return ids end
      GC.db.settings.sniper.minimumProfitCopper = 50000
      GC.db.settings.sniper.minimumRoi = 0.10
      GC.Data.GetItemValue = function() return { mv = 100000 } end -- mv only, no stressUnit
      GC.Sniper._UpdateEmptyState(0)
      assert.is_true(emptyText.shown)
      assert.matches("Import from goldcap.gg to arm the sniper", emptyText.text)
    end)

    it("still shows the refused/screened message once at least one item can arm", function()
      local GC, _, emptyText = loadSniper()
      GC.db.imported = { ts = 1000 }
      local ids = { 1 }
      GC.Data.FactItemIds = function() return ids end
      GC.db.settings.sniper.minimumProfitCopper = 50000
      GC.db.settings.sniper.minimumRoi = 0.10
      GC.Data.GetItemValue = function() return { mv = 250000, stressUnit = 200000 } end
      set(GC.Sniper._UpdateEmptyState, "refusedCount", 3)
      GC.Sniper._UpdateEmptyState(0)
      assert.matches("3 refused by live checks", emptyText.text)
    end)

    it("memoizes the armed check -- an unchanged import only walks GetItemValue once, a settings change forces one recompute", function()
      local GC, _, emptyText = loadSniper()
      GC.db.imported = { ts = 1000 }
      local ids = { 1 }
      GC.Data.FactItemIds = function() return ids end
      GC.db.settings.sniper.minimumProfitCopper = 50000
      GC.db.settings.sniper.minimumRoi = 0.10
      local calls = 0
      GC.Data.GetItemValue = function()
        calls = calls + 1
        return { mv = 100000 } -- no stressUnit: never arms -- the empty-board-on-a-large-import
        -- case the finding is about, where a per-tick re-walk would be worst.
      end

      GC.Sniper._UpdateEmptyState(0)
      GC.Sniper._UpdateEmptyState(0)
      GC.Sniper._UpdateEmptyState(0)
      assert.equals(1, calls) -- three ticks over an unchanged import: only the first walks it
      assert.is_true(emptyText.shown)

      GC.db.settings.sniper.minimumProfitCopper = 60000
      GC.Sniper._UpdateEmptyState(0)
      assert.equals(2, calls) -- the settings change invalidates the cache: exactly one recompute
    end)

    it("says nothing while a scan is streaming -- the status line narrates that", function()
      local GC, _, emptyText = loadSniper()
      emptyText.shown = true
      -- GC.Sniper._bookPass is a field now, not an upvalue -- swap in a fake reporting
      -- IsPaging() true rather than reaching for a removed local.
      GC.Sniper._bookPass = { IsPaging = function() return true end }
      GC.Sniper._UpdateEmptyState(0)
      assert.is_false(emptyText.shown)
    end)
  end)
end)
