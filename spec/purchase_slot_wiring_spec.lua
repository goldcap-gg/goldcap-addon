local helper = require("spec.spec_helper")

-- Behavioural counterpart to the static assertion in sniper_purchase_wiring_spec.lua: proves
-- GC.Sniper.IsPurchaseQuiet() actually consults GC.PurchaseSlot.IsBusy(), not a bare Owner()
-- read -- a stale BUY claim must not veto the scanner/pre-warm/drill queue/arbiter for the rest
-- of the session. Preamble copied from spec/slot_arbiter_spec.lua's load(), the smallest
-- fixture in this suite that gets UI/SniperFrame.lua to load cleanly.
describe("GC.PurchaseSlot wired into the sniper's quiet zone", function()
  local function load()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return false end,
      GetBrowseResults = function() return {} end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      SearchForItemKeys = function() end,
    }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
      Scanner = { New = function() return {} end },
      Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
        ReasonText = function(t) return tostring(t) end },
      FullScan = {
        RowsFromBrowse = function() return {} end,
        EvaluateDelta = function() return {}, 0, 0 end,
        CollectNewHot = function() return {} end,
        MergeDeals = function(existing) return existing end,
        CapDeals = function(deals) return deals end,
      },
      WatchSet = { Observe = function() end, Select = function() return {} end },
      Print = function() end,
      db = { settings = { sniper = { sound = false, board = "items" } } },
    }
    helper.loadModule("Core/PurchaseSlot.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    GC.Sniper.scanner = { Wants = function() return false end, OnSystemReady = function() end }
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.C_AuctionHouse = nil
  end)

  it("vetoes the quiet zone while BUY's claim is live, and stops once it goes stale", function()
    local GC = load()
    assert.is_false(GC.Sniper.IsPurchaseQuiet()) -- baseline: nothing in flight

    assert.is_true(GC.PurchaseSlot.Claim("buy", 100))
    assert.is_true(GC.Sniper.IsPurchaseQuiet())

    -- Still inside MAX_SECONDS: still vetoed.
    _G.GetTime = function() return 100 + GC.PurchaseSlot.MAX_SECONDS end
    assert.is_true(GC.Sniper.IsPurchaseQuiet())

    -- Past MAX_SECONDS: BUY's claim is stale, IsBusy() is false, and nothing else in this
    -- fixture is mid-flight -- the veto must lift on its own, with no explicit Release call.
    _G.GetTime = function() return 100 + GC.PurchaseSlot.MAX_SECONDS + 1 end
    assert.is_false(GC.Sniper.IsPurchaseQuiet())
    assert.equal("buy", GC.PurchaseSlot.Owner()) -- staleness only lifts the veto, not the claim itself
  end)
end)
