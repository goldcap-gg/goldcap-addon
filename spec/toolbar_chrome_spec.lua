local helper = require("spec.spec_helper")

-- Fix round (C1/I1 on the toolbar rework): `status` is a shared cross-view channel --
-- SellFrame.lua's setStatus routes ~40 user-facing messages through it -- and must survive
-- setView's Deals-only chrome toggle, while `sessionText` must never be left showing a stale
-- or zero-buy figure. Self-contained per house style; reaches setView/refreshSessionText the
-- same debug.getupvalue way spec/auto_verify_spec.lua and spec/sniper_pin_feedback_spec.lua
-- already do (see their own comments on the seam: every closure in the SniperFrame.lua chunk
-- shares the same upvalue cell for a given module-local, so setting one through any function
-- that reaches it sets it for all of them).
describe("Toolbar chrome: shared status channel + honest session block", function()
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

  local function widget()
    local w = { shown = false }
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:SetActive(active) self.active = active end
    function w:SetText(text) self.text = text end
    function w:SetTextColor(...) self.color = { ... } end
    return w
  end

  local function loadSniper()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.GetCoinTextureString = function(copper) return tostring(copper) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}

    local GC = {
      Theme = {
        ROW_H = 20,
        RAIL_W = 76,
        pad = { m = 8, s = 4, xs = 2 },
        tier = { WATCH = { 1, 1, 1 } },
        color = { watch = { 0.35, 0.72, 0.90 }, gold = { 0.83, 0.64, 0.22 }, fgDim = { 0.5, 0.5, 0.5 },
          fg = { 0.92, 0.91, 0.89 }, green = { 0, 1, 0 }, red = { 1, 0, 0 } },
      },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end }
      end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      Data = { GetItemValue = function() return nil end },
      FullScan = {},
      -- setView's Sell branch calls these directly.
      Sell = { Show = function() end, Hide = function() end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("UI/SniperFrame.lua", GC)
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer, _G.Item = nil, os.time, nil, nil
    _G.GetCoinTextureString, _G.ITEM_QUALITY_COLORS = nil, nil
  end)

  it("status stays shown after switching off Deals -- it is a shared cross-view channel, not deals-only chrome", function()
    local GC = loadSniper()
    -- createFrame is a direct upvalue of OnAuctionHouseShow (it calls `frame = frame or
    -- createFrame()`); setView is a direct upvalue of createFrame (its rail buttons' OnClick
    -- closures call it) -- neither hop requires actually invoking createFrame's real widget
    -- construction.
    local createFrame = upvalue(GC.Sniper.OnAuctionHouseShow, "createFrame")
    local setView = upvalue(createFrame, "setView")

    local status = widget()
    status.shown = true -- SellFrame.setStatus keeps writing through this while Sell is showing
    local fakeFrame = {
      scroll = widget(), headerRow = widget(),
      -- Deals-only widgets ONLY -- status is deliberately absent, matching the real
      -- f.dealsChrome built in createFrame after the C1 fix.
      dealsChrome = { widget(), widget(), widget(), widget(), widget() },
      dealsTab = widget(), sellTab = widget(), soldTab = widget(),
      status = status,
    }
    set(setView, "frame", fakeFrame)

    setView("sell")

    assert.is_true(status.shown)
  end)

  it("refreshSessionText hides the session block when the session has zero buys", function()
    local GC = loadSniper()
    -- refreshSessionText is a direct upvalue of OnAuctionHouseShow: its 0.25s ticker closure
    -- calls it by name, which pulls it into OnAuctionHouseShow's own upvalue chain too (see
    -- this file's describe-block comment on the shared-cell seam).
    local refreshSessionText = upvalue(GC.Sniper.OnAuctionHouseShow, "refreshSessionText")

    local sessionText = widget()
    sessionText.shown = true -- starts visible, so the assertion below proves a real flip
    set(refreshSessionText, "frame", { sessionText = sessionText })
    GC.Sniper.session.buys = 0

    refreshSessionText()

    assert.is_false(sessionText.shown)
  end)

  -- I1(b): OnAuctionHouseClosed's session wipe plus its own refreshSessionText() call,
  -- exercised directly against refreshSessionText rather than through the full
  -- GC.Sniper.OnAuctionHouseClosed pipeline (stopScanning/abortFullScan/resetAllPurchases/...),
  -- which needs a much larger stub surface for no additional coverage of THIS behavior -- the
  -- fix is entirely "wipe the session fields, then call refreshSessionText()", and that is
  -- exactly what this test drives.
  it("simulates an AH-close session wipe: refreshSessionText hides a stale session block on Deals", function()
    local GC = loadSniper()
    local refreshSessionText = upvalue(GC.Sniper.OnAuctionHouseShow, "refreshSessionText")

    local sessionText = widget()
    set(refreshSessionText, "frame", { sessionText = sessionText })

    -- A session with buys, rendered once mid-visit (the module-local `view` defaults to
    -- "deals", matching the toolbar's own view at that point).
    GC.Sniper.session.buys, GC.Sniper.session.spent, GC.Sniper.session.estProfit = 2, 500, 900
    refreshSessionText()
    assert.is_true(sessionText.shown)

    -- ...the wipe GC.Sniper.OnAuctionHouseClosed performs (session fields zeroed), immediately
    -- followed by the same refreshSessionText() call the fix added right after it.
    GC.Sniper.session.buys, GC.Sniper.session.spent, GC.Sniper.session.estProfit = 0, 0, 0
    refreshSessionText()

    assert.is_false(sessionText.shown)
  end)
end)
