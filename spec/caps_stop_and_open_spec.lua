local helper = require("spec.spec_helper")

-- Live price caps, final review I5 + I6: what drainCapPings is allowed to do to the screen.
-- It rings the board (pingNewHotDeals, floored per item exactly as stampVerdict's own bell is)
-- and, when the player has opted in, reuses the row's own click path to open the buy window.
-- Neither reaches a protected purchase call -- those stay behind onDialogPrimaryClick's
-- hardware click (spec/sniper_purchase_wiring_spec.lua) -- but "opens a window" is still an
-- action taken out of the player's hands, so it may never take a window away from them.
describe("Caps stop-and-open", function()
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

  local now, clicked, rung

  local function load(stopAndOpen)
    now, clicked, rung = 100, {}, {}
    _G.GetTime = function() return now end
    _G.time = function() return 1000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
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
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
          fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 } } },
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
      db = { settings = { sniper = { sound = false, board = "items",
        capStopAndOpen = stopAndOpen and true or false } } },
    }
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local drain = upvalue(upvalue(GC.Sniper.OnAuctionHouseShow, "refreshRows"), "drainCapPings")
    -- Hooks in place of the two things this may reach: the row's own click path, and the bell.
    set(drain, "onBuyClick", function(row) clicked[#clicked + 1] = row end)
    set(drain, "pingNewHotDeals", function(list) rung[#rung + 1] = list end)
    return GC, drain
  end

  local function fakeRow(deal)
    return { deal = deal, IsShown = function() return true end }
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetCoinTextureString, _G.C_Timer = nil, os.time, nil, nil
    _G.C_AuctionHouse = nil
  end)

  it("opens the buy window for the row it just rang", function()
    local GC, drain = load(true)
    local deal = { itemID = 42, unitPrice = 80, cap = 100 }
    local row = fakeRow(deal)
    set(drain, "rows", { row })

    drain({ deal })

    assert.same({ row }, clicked)
    assert.equal(GC.Sniper._rangAt[42], 100)
  end)

  it("leaves a dialog the player is reading for another row exactly where it is", function()
    local _, drain = load(true)
    local deal = { itemID = 42, unitPrice = 80, cap = 100 }
    local row, otherRow = fakeRow(deal), fakeRow({ itemID = 7 })
    set(drain, "rows", { row })
    set(drain, "dialog", { row = otherRow })

    drain({ deal })

    assert.same({}, clicked)
  end)

  it("still reaches the row whose dialog is already open (it only needs raising)", function()
    local _, drain = load(true)
    local deal = { itemID = 42, unitPrice = 80, cap = 100 }
    local row = fakeRow(deal)
    set(drain, "rows", { row })
    set(drain, "dialog", { row = row })

    drain({ deal })

    assert.same({ row }, clicked)
  end)

  it("opens one window per drain, not one per hit", function()
    local _, drain = load(true)
    local first = { itemID = 42, unitPrice = 80, cap = 100 }
    local second = { itemID = 43, unitPrice = 80, cap = 100 }
    local rowA, rowB = fakeRow(first), fakeRow(second)
    set(drain, "rows", { rowA, rowB })

    drain({ first, second })

    assert.same({ rowA }, clicked)
  end)

  it("opens nothing at all when the player has not opted in", function()
    local _, drain = load(false)
    local deal = { itemID = 42, unitPrice = 80, cap = 100 }
    set(drain, "rows", { fakeRow(deal) })

    drain({ deal })

    assert.same({}, clicked)
    assert.equal(1, #rung) -- the bell is not the opt-in; it always rings
  end)

  -- I6: the same per-item floor stampVerdict's own bell observes. A capped commodity whose
  -- book churns under the cap announces on every improvement, and every one of those still
  -- SHOWS on the board -- but a bell every few seconds stops carrying information.
  describe("the ring floor", function()
    it("does not ring the same item twice inside the floor", function()
      local _, drain = load(false)
      local deal = { itemID = 42, unitPrice = 80, cap = 100 }
      drain({ deal })
      assert.equal(1, #rung[1])

      now = now + 5
      drain({ { itemID = 42, unitPrice = 70, cap = 100 } })
      assert.same({}, rung[2])
    end)

    it("rings again once the floor has passed", function()
      local _, drain = load(false)
      drain({ { itemID = 42, unitPrice = 80, cap = 100 } })

      now = now + 3600
      drain({ { itemID = 42, unitPrice = 70, cap = 100 } })
      assert.equal(1, #rung[2])
    end)

    it("never lets one item silence a different one", function()
      local _, drain = load(false)
      drain({ { itemID = 42, unitPrice = 80, cap = 100 } })

      now = now + 5
      drain({ { itemID = 43, unitPrice = 80, cap = 100 } })
      assert.equal(1, #rung[2])
    end)
  end)
end)
