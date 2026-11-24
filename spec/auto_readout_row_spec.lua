local helper = require("spec.spec_helper")
local Font = require("spec.support.font_metrics")

-- The row at the window's minimum width (640): the tabs, the toggle on the Items board, and the
-- readout in what is left, measured in the shipped faces in the longest languages.
describe("AUTO readout in the tabs' row", function()
  local MEDIA = "GoldCap/Media/"
  local HEAD, TEXT, MONO = Font.load(MEDIA .. "FiraSansCondensed-Bold.ttf"), Font.load(MEDIA .. "FiraSans-Medium.ttf"),
    Font.load(MEDIA .. "FiraMono-Medium.ttf")
  local BOARD_TAB = { H = 36, ICON = 24, PAD = 6, GAP = 8 }
  local GC

  local function load(code)
    _G.GetTime = function() return 100 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    GC = {
      Theme = { ROW_H = 32, RAIL_W = 76, Scale = function() return 1 end, BOARD_TAB = BOARD_TAB,
        pad = { xs = 4, s = 8, m = 12, l = 16 }, tier = { WATCH = { 1, 1, 1 } },
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
    helper.loadModule("Core/AutoReadout.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    if code ~= "enUS" then helper.loadModule("Locale/" .. code .. ".lua", GC) end
    GC.ActivateLocale(code)
  end
  after_each(function() _G.GetTime, _G.C_Timer, _G.Item = nil, nil, nil end)

  -- A board tab as Theme.BoardTab fits it (UI/Kit/Button.lua): its name in the heading face at 10,
  -- the line under it in the text face at 9, both at the font scale.
  local function tab(name, sub, scale)
    local t = { sub = true, points = {} }
    function t:ShowSub(on) self.sub = on end
    function t:Fit()
      local words = HEAD:width(GC.L[name], 10 * scale)
      if self.sub then words = math.max(words, TEXT:width(GC.L[sub], 9 * scale)) end
      self.w = math.ceil(BOARD_TAB.PAD + BOARD_TAB.ICON + BOARD_TAB.GAP + words + BOARD_TAB.PAD + 4)
    end
    function t:GetWidth() return self.w end
    t:Fit()
    return t
  end

  local function region(shown, width)
    local r = { shown = shown, w = width }
    function r:IsShown() return self.shown end
    function r:GetWidth() return self.w end
    function r:ClearAllPoints() self.point = nil end
    function r:SetPoint(...) self.point = { ... } end
    function r:SetWidth(w) self.w = w end
    function r:SetAlpha() end
    return r
  end

  local function row(code, layout, scale, windowWidth)
    load(code)
    GC.Theme.Scale = function() return scale end
    local chips = { commodities = tab("COMMODITIES", "herbs, ore, potions", scale),
      items = tab("ITEMS", "gear, pets, recipes", scale) }
    if layout.forever then chips.blackwater = tab("BLACKWATER", "buy there, sell here", scale) end
    local lackW = math.max(96, math.ceil(HEAD:width(GC.L["Only what I lack"]:upper(), 10 * scale) + 24))
    local owner = { boardChips = chips, boardY = -64, boardRowH = 36, _readoutOn = true,
      lackToggle = region(layout.lack, lackW), sessionText = region(false), goldLine = region(layout.gold or false),
      readoutTop = region(true), readoutBottom = region(true) }
    function owner:GetWidth() return windowWidth or 640 end
    GC.Sniper._LayoutBoardRow(owner)
    local tabs = 0
    for _, chip in pairs(chips) do tabs = tabs + chip:GetWidth() + 4 end
    return owner, tabs, lackW
  end

  local counts = { finds = 31, checked = 29, deals = 4 }
  local LAYOUTS = {
    { what = "retail Commodities", lack = false,
      state = { pass = { page = 14, lapPages = 27, items = 12300, seconds = 21 }, counts = counts, perMinute = 58 } },
    { what = "retail Items, with Only what I lack", lack = true,
      state = { items = { targets = 512, round = 4, batch = 2, batches = 6 }, counts = counts, perMinute = 58 } },
    { what = "WoW: Forever, three tabs", lack = false, forever = true,
      state = { pass = { page = 5, lapPages = 8, items = 900, seconds = 11 }, full = { dueIn = 540 },
        counts = counts, perMinute = 40 } },
  }

  for _, code in ipairs({ "enUS", "deDE", "frFR", "ruRU", "ukUA" }) do
    for _, layout in ipairs(LAYOUTS) do
      for _, scale in ipairs({ 1.0, 1.3 }) do
        it(("%s, %s, font scale %.1f: whole words, never over a tab"):format(code, layout.what, scale), function()
          local owner, tabs, lackW = row(code, layout, scale)
          local width = owner._readoutWidth
          -- From the window's right edge (640 - the scrollbar gutter) back to where the tabs end.
          local content = 640 - (76 + 12) - 32
          assert.is_true(width >= 0)
          assert.is_true(tabs + 12 + width + (layout.lack and lackW + 12 or 0) <= content,
            ("the readout (%d) reaches the tabs (%d)"):format(width, tabs))
          local lines = GC.AutoReadout.Lines(layout.state)
          local function measure(text) return MONO:width(text, 10 * scale) end
          local first = GC.AutoReadout.Fit(lines.now, width, measure)
          local second = GC.AutoReadout.Fit(lines.recent, width, measure)
          -- Every rung is a whole line of whole parts; what fits is one of them, or nothing.
          for _, fitted in ipairs({ first or "", second or "" }) do
            assert.is_falsy(fitted:find("...", 1, true))
            assert.is_falsy(fitted:find("…", 1, true))
          end
          -- At the default scale both lines always say something, at least the page and the deals.
          if scale == 1.0 then
            assert.is_truthy(first, ("%s: no line 1 in %dpx"):format(code, width))
            assert.is_truthy(second, ("%s: no line 2 in %dpx"):format(code, width))
          end
          -- At the largest, German and Russian keep at least the deals.
          if code == "deDE" or code == "ruRU" then
            assert.is_truthy(second, ("%s: no line 2 in %dpx"):format(code, width))
          end
        end)
      end
    end
  end

  it("keeps the tabs' lines in the docked auction house (792) beside the whole readout", function()
    for _, code in ipairs({ "enUS", "deDE", "ruRU" }) do
      local owner = row(code, { lack = false }, 1.0, 792)
      assert.is_true(owner.boardChips.commodities.sub, code)
      assert.equal(280, owner._readoutWidth, code)
    end
  end)

  it("gives the gold line its room first, and the readout what is left", function()
    local owner = row("deDE", { lack = false, gold = true }, 1.0)
    local free = row("deDE", { lack = false }, 1.0)
    assert.is_true(owner._readoutWidth < free._readoutWidth)
  end)

  it("puts the toggle left of the readout, under the square buttons the readout keeps", function()
    local owner = row("enUS", { lack = true }, 1.0)
    assert.is_true(owner._readoutWidth > 0)
    assert.equal(-32, owner.readoutTop.point[4])
    assert.equal(-32 - owner._readoutWidth - 12, owner.lackToggle.point[4])
  end)

  it("reads as paused when the chip does, and at work on the Items board while its poll runs", function()
    load("enUS")
    assert.is_false(GC.Sniper._AutoReadoutPaused("PAUSED", { items = true }))
    assert.is_false(GC.Sniper._AutoReadoutPaused("SCANNING", {}))
    assert.is_true(GC.Sniper._AutoReadoutPaused("PAUSED", { items = true, mail = true }))
    assert.is_true(GC.Sniper._AutoReadoutPaused("PAUSED", { sell = true }))
    assert.is_true(GC.Sniper._AutoReadoutPaused("OFF", {}))
  end)
end)
